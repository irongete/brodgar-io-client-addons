-- The client's own meters: finding the one a bar reads, hiding it while this addon draws its own, and
-- the amount the server states for health.

local Config = HUD.Config

local Meters = {}
HUD.Meters = Meters

-- A Meter is interned and answers :exists(), so one found for a character is kept until that meter leaves
-- the HUD. Without the cache every bar would walk the meter list once per frame.
local meterCache = {}                        -- [Session] = {[resource name] = Meter}

function Meters.find(session, resourceName)
  local perSession = meterCache[session]
  if perSession == nil then
    perSession = {}
    meterCache[session] = perSession
  end

  local held = perSession[resourceName]
  if (held ~= nil) and held:exists() then return held end
  perSession[resourceName] = nil

  -- :find(needle) is a substring match and a meter the server adds later could carry another bar's name
  -- inside its own, so the whole resource name is compared.
  for _, candidate in ipairs(session:meter():list()) do
    if candidate:res() == resourceName then
      perSession[resourceName] = candidate
      return candidate
    end
  end
  return nil
end

-- ---------------------------------------------------------------- hiding the client's meters

-- What this addon hid, so what it puts back is exactly that: [Session] = {[resource name] = Widget}. A
-- meter hidden by the client or by another addon was never in here and is never touched.
local hiddenWidgets = {}

function Meters.restore(session)
  local held = hiddenWidgets[session]
  if held == nil then return end
  for resourceName, widget in pairs(held) do
    if widget:exists() then widget:visible(true) end
    held[resourceName] = nil
  end
  hiddenWidgets[session] = nil
end

function Meters.restoreAll()
  for session in pairs(hiddenWidgets) do Meters.restore(session) end
end

-- Hides the client's meter for every bar in Config.BARS while the addon is enabled, and gives them back
-- when it is not. The extra bars a mount adds are not in BARS and stay the client's to draw.
local function reconcile()
  if not Config.enabledOption:value() then
    Meters.restoreAll()
    return
  end

  for _, session in ipairs(hafen.session():list()) do
    local held = hiddenWidgets[session]
    if held == nil then
      held = {}
      hiddenWidgets[session] = held
    end
    for _, bar in ipairs(Config.BARS) do
      local widget = held[bar.resource]
      if (widget ~= nil) and (not widget:exists()) then    -- a character switch rebuilds the HUD
        widget = nil
        held[bar.resource] = nil
      end
      if widget == nil then
        local meter = Meters.find(session, bar.resource)
        local meterWidget = meter and meter:widget()
        if (meterWidget ~= nil) and meterWidget:exists() then
          meterWidget:visible(false)
          held[bar.resource] = meterWidget
        end
      end
    end
  end
end

-- An option's Changed handler runs inside the Options window's tree and a meter belongs to the game's, so
-- the reconcile is moved onto the step (api/threading.md). MeterAdded takes the same door: its meter can
-- still be loading its resource while the handler runs.
local reconcileQueued = false

function Meters.reconcileSoon()
  if reconcileQueued then return end
  reconcileQueued = true
  hafen.timer():after(0, function()
    reconcileQueued = false
    reconcile()
  end)
end

-- ---------------------------------------------------------------- the amount the server states

-- The percentage a bar writes is arithmetic over the segment the server publishes; the amount is the
-- server's own words, and rides in the "tip" update sent to the meter widget. The update is caught on
-- the way in rather than read back off the widget, which only keeps it when the server sends one string:
-- sent as an info array, the client builds the line at hover time and the tooltip is never set.
local statedTips = {}                        -- [Session] = {[resource name] = {amount =, args =}}

-- What is in brackets, else a run of numbers separated by slashes.
local AMOUNT_PATTERNS = {"%(([^%)]*%d[^%)]*)%)", "(%d+%s*/[%d%s/]*%d)"}
local MAX_TIP_DEPTH = 5

-- The first amount anywhere in the message. A tip is either the line itself or an array the line is built
-- from, so the search walks whatever arrived rather than assuming one shape.
local function amountIn(value, depth)
  if type(value) == "string" then
    for _, pattern in ipairs(AMOUNT_PATTERNS) do
      local found = string.match(value, pattern)
      if found ~= nil then return found end
    end
    return nil
  end
  if (type(value) ~= "table") or (depth >= MAX_TIP_DEPTH) then return nil end
  for _, inner in pairs(value) do
    local found = amountIn(inner, depth + 1)
    if found ~= nil then return found end
  end
  return nil
end

-- Which bar the update is addressed to, if any. The widget is the identity: a Widget is interned, so ==
-- answers it, where the line's own wording is the server's and may be anything.
local function barOfWidget(sourceWidget)
  for _, session in ipairs(hafen.session():list()) do
    for _, bar in ipairs(Config.BARS) do
      local meter = Meters.find(session, bar.resource)
      if (meter ~= nil) and (meter:widget() == sourceWidget) then return session, bar end
    end
  end
  return nil, nil
end

-- An inbound message handler holds no widget tree (api/event/streams.md), so the reads above are legal.
hafen.event():message():on("tip", function(event)
  local sourceWidget = event:widget()
  if (sourceWidget == nil) or (sourceWidget:type() ~= "IMeter") then return end
  local session, bar = barOfWidget(sourceWidget)
  if bar == nil then return end

  local perSession = statedTips[session]
  if perSession == nil then
    perSession = {}
    statedTips[session] = perSession
  end
  local args = event:args()
  perSession[bar.resource] = {amount = amountIn(args, 0), args = args}
end)

-- Reads a client widget when no tip has been caught yet, so callers run on the engine step.
function Meters.statedAmount(session, bar)
  local perSession = statedTips[session]
  local stated = perSession and perSession[bar.resource]
  if stated ~= nil then return stated.amount end

  -- Nothing caught yet: the meter has not moved since the addon was loaded. The widget may still hold the
  -- line the server sent before that, in the one case where it keeps it.
  local meter = Meters.find(session, bar.resource)
  local meterWidget = meter and meter:widget()
  local tip = meterWidget and meterWidget:tooltip()
  if tip == nil then return nil end
  return amountIn(tip, 0)
end

-- A character switch rebuilds the HUD, and what the old one was told is the old character's.
function Meters.forget(session)
  meterCache[session] = nil
  statedTips[session] = nil
end

-- The session is gone: its widget tree went with it, so there is nothing left to put back.
function Meters.drop(session)
  Meters.forget(session)
  hiddenWidgets[session] = nil
end

-- Writes what the server last sent for the bars of the character on screen. The wording is the server's
-- and can change under AMOUNT_PATTERNS; this shows what actually arrived.
hafen.console():on("hud-tip", function()
  local session = hafen.session():current()
  local perSession = session and statedTips[session]
  if perSession == nil then
    hafen.log():write("hud: no meter tip seen yet -- let a bar move first")
    return
  end
  for resourceName, stated in pairs(perSession) do
    local succeeded, encoded = pcall(function() return hafen.json():encode(stated.args) end)
    hafen.log():write(("hud: %s amount=%s raw=%s")
      :format(resourceName, tostring(stated.amount), succeeded and encoded or tostring(encoded)))
  end
end)
