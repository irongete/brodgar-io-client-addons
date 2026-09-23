-- Hiding what the ticks name, the patches laid where it stood, the hotkey and the world events.
--
-- A patch anchored to a gob follows it over the ground, is hidden by whatever stands in front of it, and
-- ends with the gob.

local Options = Hider.Options

local FALLBACK_HALF_SIDE = 5.5      -- half-side of the square laid for an object carrying no footprint
local RESCAN_SECONDS = 2            -- between full sweeps of the gob list
local SETTLE_SECONDS = 0.1          -- a look change waits this long before the patches are re-dressed

-- [session] = {active = boolean, hiddenGobs = {[gob] = true, ...}}
local sessionStates = {}

-- [gob] = {patches = {patch, ...}, fromHitbox = boolean}. gob:visible() and a patch are written on the
-- object rather than on a character, so the marks are keyed on the gob and not held per session.
local laidMarks = {}

local function stateFor(session)
  local state = sessionStates[session]
  if not state then
    state = {active = false, hiddenGobs = {}}
    sessionStates[session] = state
  end
  return state
end

local function isHidden(resourceName)
  local kind = Hider.kindOf(resourceName)
  return kind ~= nil and Options.hides(kind)
end

local function patchCollection()
  return hafen.virtual():patch()
end

local function dress(patch)
  return patch:tint(Options.fillColour()):border(Options.borderColour(), Options.borderWidth())
end

-- position:offset() answers nil on ground the character on screen cannot locate.
local function squareRing(position)
  local half = FALLBACK_HALF_SIDE
  local northWest = position:offset(-half, -half)
  local northEast = position:offset(half, -half)
  local southEast = position:offset(half, half)
  local southWest = position:offset(-half, half)
  if northWest and northEast and southEast and southWest then
    return {{northWest, northEast, southEast, southWest}}
  end
end

-- The rings to lay for one object, and whether they are its own footprint. gob:hitbox() reads nil until the
-- object's resource resolves, and for a resource that carries no shape of its own.
local function ringsFor(gob)
  local hitbox = gob:hitbox()
  if hitbox and (#hitbox > 0) then return hitbox, true end
  local position = gob:position()
  if not position then return nil, false end
  return squareRing(position), false
end

-- The collection refuses a ring it cannot lay (concave, or past the 32-edge limit); that ring is skipped
-- and the rest of the set is still laid.
local function layRing(gob, ring, patches)
  local laid, patch = pcall(function()
    return dress(patchCollection():add(ring, gob))
  end)
  if laid and patch then patches[#patches + 1] = patch end
end

local function layMark(gob)
  if laidMarks[gob] then return end
  local rings, fromHitbox = ringsFor(gob)
  if not rings then return end
  local patches = {}
  for _, ring in ipairs(rings) do layRing(gob, ring, patches) end
  if #patches > 0 then laidMarks[gob] = {patches = patches, fromHitbox = fromHitbox} end
end

local function removeMark(gob)
  local mark = laidMarks[gob]
  if not mark then return end
  laidMarks[gob] = nil
  for _, patch in ipairs(mark.patches) do
    if patch:exists() then patchCollection():remove(patch) end
  end
end

local function redress()
  for _, mark in pairs(laidMarks) do
    for _, patch in ipairs(mark.patches) do
      if patch:exists() then dress(patch) end
    end
  end
end

-- A gob keeps its id when its resource changes (a felled tree becomes a log), so the name is read again on
-- every sweep. A nil name is an object whose resource has not arrived yet.
local function considerGob(state, gob)
  local resourceName = gob:name()
  if resourceName == nil then return end
  if isHidden(resourceName) then
    if not state.hiddenGobs[gob] then
      state.hiddenGobs[gob] = true
      gob:visible(false)
    end
    layMark(gob)
  elseif state.hiddenGobs[gob] then
    state.hiddenGobs[gob] = nil
    gob:visible(true)
    removeMark(gob)
  end
end

-- An object hidden before its resource resolved wears the fallback square, and is re-laid once, when its
-- own footprint can be read. Taking a patch up and putting it down re-cuts the tiles under it, so it is
-- not re-laid on every sweep.
local function relayFallbackMark(gob)
  local mark = laidMarks[gob]
  if mark and not mark.fromHitbox and gob:hitbox() then
    removeMark(gob)
    layMark(gob)
  end
end

local function sweep(session, state)
  if not session:character() then return end
  for _, gob in ipairs(session:world():gob():list()) do
    considerGob(state, gob)
    relayFallbackMark(gob)
  end
end

local function sweepActive()
  for session, state in pairs(sessionStates) do
    if state.active then sweep(session, state) end
  end
end

local function unhideAll(state)
  for gob in pairs(state.hiddenGobs) do
    gob:visible(true)
    removeMark(gob)
  end
  state.hiddenGobs = {}
  state.active = false
end

hafen.timer():every(RESCAN_SECONDS, sweepActive)

hafen.client():options():keybindings():on("toggle", function()
  local session = hafen.session():current()
  if not session then return end
  local state = stateFor(session)
  if state.active then
    unhideAll(state)
  else
    state.active = true
    sweep(session, state)
  end
end)

-- An option's Changed handler runs inside the Options window's widget tree, and a tick sweeps every gob in
-- view, so the work is moved onto a timer step (api/threading.md). A tick ticked brings its objects out of
-- the scene at once; unticked, the same sweep puts them back.
Options.onKindsChanged(function()
  hafen.timer():after(0, sweepActive)
end)

-- A slider fires Changed on every step of a drag; the re-dress is debounced onto one restarted timer.
local settleTimer
Options.onLookChanged(function()
  if settleTimer then settleTimer:cancel() end
  settleTimer = hafen.timer():after(SETTLE_SECONDS, function()
    settleTimer = nil
    redress()
  end)
end)

-- GobAdded fires before the object's first drawn frame, once per object whichever session sees it, so it is
-- offered to each of them in turn.
hafen.event():on("GobAdded", function(gob)
  for _, session in ipairs(gob:sessions():list()) do
    local state = sessionStates[session]
    if state and state.active then considerGob(state, gob) end
  end
end)

-- A patch anchored to a gob is removed with the gob, and gob:sessions() answers empty here: only the
-- records go.
hafen.event():on("GobRemoved", function(gob)
  laidMarks[gob] = nil
  for _, state in pairs(sessionStates) do state.hiddenGobs[gob] = nil end
end)

hafen.event():on("SessionRemoved", function(session)
  sessionStates[session] = nil
end)
