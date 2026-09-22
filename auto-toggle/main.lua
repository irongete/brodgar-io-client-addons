-- Auto Toggle: turns on the picked Adventure > Toggle entries when a character enters the world.
--
-- Surfaces: the grid on Options > AddOns > Auto Toggle. No window, no command, no console output.

local SQUARE  = 34                       -- the client's inventory square, design px
local ICON    = 32                       -- the square less its one-pixel ring
local GAP     = 2
local PITCH   = SQUARE + GAP
local COLUMNS = 8                        -- (8 * 36) - 2 = 286 px, inside the 410 px options page box

-- haven.Inventory builds its square in code, so there is no resource to draw it by.
local SLOT_FILL = {36, 52, 38, 125}
local SLOT_EDGE = {20, 28, 21, 167}
local OFF_TINT  = {90, 90, 90, 255}      -- multiplies the icon down while its toggle is not picked

local SETTLE   = 3                       -- seconds before the menu and the buff bar are read at login
local INTERVAL = 0.5                     -- seconds between retries
local DEADLINE = 20                      -- seconds before what is still not ready is abandoned

-- The addon's own var, shared by every character on this client:
--   catalogue  {res =, name =} per toggle, in menu order
--   picked     [res] = true for the toggles turned on at login
local saved = hafen.store():var("toggles")
saved.catalogue = saved.catalogue or {}
saved.picked = saved.picked or {}

-- ---------------------------------------------------------------- the catalogue

-- Resolved through a toggle every character has rather than by the category's caption: a translated
-- client renames the caption and keeps the resource.
local ANCHORS = {"paginae/act/swim", "paginae/act/crime"}

local function toggleCategory(session)
  local menugrid = session:menugrid()
  for _, resourceName in ipairs(ANCHORS) do
    local entry = menugrid:get(resourceName)
    local category = entry and entry:parent()
    if category then
      return category
    end
  end
  return menugrid:get("Toggle")
end

-- Every toggle that character has, in menu order. Kept in the store so the page has a grid to draw with
-- nobody logged in; a menu still streaming in returns nothing and leaves the stored list standing.
local function catalogue(session)
  local category = session and session:exists() and toggleCategory(session)
  local children = category and category:children()
  if children then
    local found = {}
    for _, entry in ipairs(children:list()) do
      local name = entry:name()
      if name then
        found[#found + 1] = {res = entry:res(), name = name}
      end
    end
    if #found > 0 then
      saved.catalogue = found
    end
  end
  return saved.catalogue
end

-- ---------------------------------------------------------------- the page

local options = hafen.client():options():addon()

-- One cell of the grid. The square is its :stock, so a theme naming it overrides the look per property;
-- the Draw reads the var every frame, so a press repaints the cell on the next one.
local function addCell(grid, toggle, index)
  local cell = hafen.ui():widget():parent(grid)
    :size(SQUARE, SQUARE)
    :position(((index - 1) % COLUMNS) * PITCH, math.floor((index - 1) / COLUMNS) * PITCH)
    :name("slot" .. index)
  cell:stock{bg = {color = SLOT_FILL}, border = {color = SLOT_EDGE, width = 1}}
  cell:tooltip(toggle.name)

  cell:on("Draw", function(drawEvent)
    local graphics = drawEvent:g()
    if not saved.picked[toggle.res] then
      graphics:color(OFF_TINT)
    end
    graphics:resource(toggle.res, 1, 1, ICON, ICON)
    graphics:color()
  end)

  cell:on("MouseDown", function(event)
    event:preventDefault()
    if saved.picked[toggle.res] then
      saved.picked[toggle.res] = nil
    else
      saved.picked[toggle.res] = true
    end
    hafen.store():flush()                -- written now rather than on the store's thirty-second timer
  end)
end

options:panel(function(root)
  root:gap(6)
  hafen.ui():label():parent(root):text("Turned on when a character enters the world")

  local toggles = catalogue(hafen.session():current())
  if #toggles == 0 then
    hafen.ui():label():parent(root):text("Log in once and this page draws that character's toggles.")
    return
  end

  -- A bare widget, not a column: a column lays its children out and refuses their :position.
  local columns = math.min(#toggles, COLUMNS)
  local rows = math.ceil(#toggles / COLUMNS)
  local grid = hafen.ui():widget():parent(root):size((columns * PITCH) - GAP, (rows * PITCH) - GAP)
  for index, toggle in ipairs(toggles) do
    addCell(grid, toggle, index)
  end

  hafen.ui():label():parent(root):text("Click an icon: full colour is on, dark is off.")
end)

-- ---------------------------------------------------------------- login

-- The server keeps a buff up while a toggle is on. Reading it is what stops a second press turning an
-- already-on toggle off.
local function alreadyOn(session, toggle)
  return (session:buff():find(toggle.res) ~= nil) or (session:buff():find(toggle.name) ~= nil)
end

-- true once the toggle is settled: pressed, or already on. false while its entry is absent from the menu
-- or its resource is still loading.
local function press(session, toggle)
  local entry = session:menugrid():get(toggle.res)
  if not (entry and entry:name()) then
    return false
  end
  if not alreadyOn(session, toggle) then
    entry:use()
  end
  return true
end

-- Retry until every picked toggle is settled, the login ends, or DEADLINE passes. A toggle that raises is
-- dropped: nothing here reaches the console.
local function run(session, pending)
  local character = session:character()
  local elapsed = 0
  local timer
  timer = hafen.timer():every(INTERVAL, function()
    elapsed = elapsed + INTERVAL
    if session:character() ~= character then
      timer:cancel()                     -- logged out, or playing someone else now
      return
    end
    if elapsed < SETTLE then
      return
    end
    for index = #pending, 1, -1 do
      local ok, settled = pcall(press, session, pending[index])
      if (not ok) or settled then
        table.remove(pending, index)
      end
    end
    if (#pending == 0) or (elapsed >= DEADLINE) then
      timer:cancel()
    end
  end)
end

-- A :reload re-announces SessionEnteredWorld for every character already in the world. That is not a
-- login, so the sessions up when this file runs are skipped once.
local reannounced = {}
for _, session in ipairs(hafen.session():list()) do
  if session:character() then
    reannounced[session:user()] = true
  end
end

hafen.event():on("SessionEnteredWorld", function(session)
  if reannounced[session:user()] then
    reannounced[session:user()] = nil
    return
  end
  local pending = {}
  for _, toggle in ipairs(saved.catalogue) do
    if saved.picked[toggle.res] then
      pending[#pending + 1] = toggle
    end
  end
  if #pending > 0 then
    run(session, pending)
  end
end)
