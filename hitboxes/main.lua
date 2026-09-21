-- Hitboxes: lays a ground patch on the footprint (gob:hitbox()) of every game object in view and of the
-- building being placed. Three modes, cycled with the key assigned in Options > Game > Keybindings >
-- Hitboxes: "off", "ground" (the world hides the patch) and "over" (patch:occluded(false)).
--
-- Every setting is an addon option (Options > AddOns > Hitboxes). The key only rotates the mode option;
-- the option's Changed handler is the single path into and out of a mode.

local RESCAN_SECONDS = 2        -- between full sweeps of the gob list
local FACING_SECONDS = 0.2      -- between facing corrections, see correctFacing()
local SETTLE_SECONDS = 0.1      -- a look change waits this long before the patches are re-dressed

local MODES = {"off", "ground", "over"}

-- The client has no colour control, so fill and border colours are picked by name.
local COLOURS = {
  {"blue",   { 60, 140, 255}},
  {"sky",    {120, 190, 255}},
  {"white",  {255, 255, 255}},
  {"grey",   {150, 150, 150}},
  {"black",  {  0,   0,   0}},
  {"red",    {255,  70,  70}},
  {"orange", {255, 150,  40}},
  {"yellow", {255, 225,  60}},
  {"green",  { 70, 220, 110}},
  {"teal",   { 40, 210, 200}},
  {"purple", {170, 110, 255}},
  {"pink",   {255, 120, 200}},
}

local COLOUR_NAMES, COLOUR_RGB = {}, {}
for index, entry in ipairs(COLOURS) do
  COLOUR_NAMES[index] = entry[1]
  COLOUR_RGB[entry[1]] = entry[2]
end

-- ---------------------------------------------------------------- options

local options = hafen.client():options():addon()

local modeOption        = options:choice("mode"):choices(MODES):default(MODES[1]):add()
local fillOption        = options:choice("fill"):choices(COLOUR_NAMES):default("blue"):add()
local opacityOption     = options:number("opacity"):range(0, 100):default(27):add()
local borderOption      = options:choice("border"):choices(COLOUR_NAMES):default("sky"):add()
local borderWidthOption = options:number("border-width"):range(0, 100):default(35):add()

-- A slider shows no number, so its label carries the value.
local function addSlider(root, caption, option, tooltip)
  local label = hafen.ui():label():parent(root):text(caption .. ": " .. option:value())
  local slider = hafen.ui():slider():parent(root):size(160):tooltip(tooltip):bind(option)
  slider:on("Changed", function(event) label:text(caption .. ": " .. event:value()) end)
end

local function addDropdown(root, caption, option, tooltip)
  hafen.ui():label():parent(root):text(caption)
  hafen.ui():dropdown():parent(root):size(120):tooltip(tooltip):bind(option)
end

options:panel(function(root)
  root:gap(4)
  addDropdown(root, "Footprints", modeOption,
              "off, laid on the ground where each object stands, or drawn through everything in front of it")
  addDropdown(root, "Fill colour", fillOption, "the colour laid over the ground an object stands on")
  addSlider(root, "Fill opacity", opacityOption,
            "per cent: how much of the ground shows through the fill. 0 leaves only the border")
  addDropdown(root, "Border colour", borderOption, "the line round the footprint, always solid")
  addSlider(root, "Border thickness", borderWidthOption,
            "hundredths of a world unit, a tile is 11 units. 0 is the thinnest line the screen can draw; " ..
            "to hide the border, give it the fill's colour")
end)

-- An option's Changed handler runs inside the Options window's widget tree, and a mode change sweeps
-- every gob in view, so the work is moved onto a timer step (api/threading.md).
local function onNextStep(callback)
  hafen.timer():after(0, callback)
end

-- A slider fires Changed on every step of a drag; the re-dress is debounced onto one restarted timer.
local settleTimer
local function afterSettle(callback)
  if settleTimer then settleTimer:cancel() end
  settleTimer = hafen.timer():after(SETTLE_SECONDS, function()
    settleTimer = nil
    callback()
  end)
end

-- ---------------------------------------------------------------- state

-- [Gob] = {name = resource name when read, patches = {patch, ...},
--          baseFacing = facing when read, rotation = last rotation written}
local laidBoxes = {}
local ghostBox              -- the same for the building being placed, plus lastX/lastY of the patches
local sweepTimer            -- running in both drawing modes; nil while "off"
local facingTimer

local function isGroundMode() return modeOption:value() == "ground" end
local function isOff()        return modeOption:value() == "off" end

local function patchCollection()
  return hafen.virtual():patch()
end

-- ---------------------------------------------------------------- look

-- A colour name the palette no longer carries falls back to the option's default.
local function colourOf(option)
  return COLOUR_RGB[option:value()] or COLOUR_RGB[option:default()]
end

-- The tint's fourth component is the fill's own opacity; the border is left solid.
local function dress(patch)
  local fill = colourOf(fillOption)
  local alpha = math.floor(((opacityOption:value() * 255) / 100) + 0.5)
  return patch:tint({fill[1], fill[2], fill[3], alpha})
              :border(colourOf(borderOption), borderWidthOption:value() / 100)
              :occluded(isGroundMode())
end

local function redress()
  for _, box in pairs(laidBoxes) do
    for _, patch in ipairs(box.patches) do
      if patch:exists() then dress(patch) end
    end
  end
  if ghostBox then
    for _, patch in ipairs(ghostBox.patches) do
      if patch:exists() then dress(patch) end
    end
  end
end

-- ---------------------------------------------------------------- laying a footprint

-- The collection refuses a ring it cannot lay (concave, or past the 32-edge limit); that ring is skipped
-- and the rest of the set is still laid.
local function layRing(anchor, ring, patches)
  local ok, patch = pcall(function()
    return dress(patchCollection():add(ring, anchor))
  end)
  if ok and patch then patches[#patches + 1] = patch end
end

local function removePatches(box)
  for _, patch in ipairs(box.patches) do
    if patch:exists() then patchCollection():remove(patch) end
  end
end

-- An object without a shape is not recorded, so the next sweep reads it again (its resource may not have
-- resolved yet).
local function layGobBox(gob, name)
  local rings = gob:hitbox()
  if not rings then return end
  local patches = {}
  for _, ring in ipairs(rings) do layRing(gob, ring, patches) end
  if #patches == 0 then return end
  laidBoxes[gob] = {name = name, patches = patches, baseFacing = gob:facing() or 0, rotation = 0}
end

local function forgetGob(gob)
  local box = laidBoxes[gob]
  if not box then return end
  laidBoxes[gob] = nil
  removePatches(box)
end

-- A gob keeps its id when its resource changes (a felled tree becomes a log), so the box is keyed on the
-- resource name and re-laid when that name changes.
local function considerGob(gob)
  local name = gob:name()
  if name == nil then return end
  local box = laidBoxes[gob]
  if box then
    if box.name == name then return end
    forgetGob(gob)
  end
  layGobBox(gob, name)
end

local function sweep()
  for _, session in ipairs(hafen.session():list()) do
    if session:character() then
      for _, gob in ipairs(session:world():gob():list()) do considerGob(gob) end
    end
  end
end

-- ---------------------------------------------------------------- facing

-- gob:hitbox() answers rings already turned by the object's facing, and a patch anchored to a gob does not
-- turn with it, so each box is rotated by how far the object has turned since its rings were read.
local function rotateBox(box, facing)
  local rotation = facing - box.baseFacing
  if rotation == box.rotation then return end
  box.rotation = rotation
  for _, patch in ipairs(box.patches) do
    if patch:exists() then patch:rotate(rotation) end
  end
end

local function correctFacing()
  for gob, box in pairs(laidBoxes) do
    local facing = gob:facing()
    if facing then rotateBox(box, facing) end
  end
end

-- ---------------------------------------------------------------- the building being placed

local function removeGhostBox()
  if not ghostBox then return end
  local box = ghostBox
  ghostBox = nil
  removePatches(box)
end

-- The placing ghost is not a gob, so its box is anchored at a position and moved from Update every frame.
-- Only the current session's ghost is drawn.
local function followGhost()
  local session = hafen.session():current()
  local placing = session and session:world():placing()
  if not placing then return removeGhostBox() end
  local name = placing:name()
  if name == nil then return end
  if ghostBox and (ghostBox.name ~= name) then removeGhostBox() end
  local position = placing:position()
  if not position then return end
  if not ghostBox then
    local rings = placing:hitbox()
    if not rings then return end
    local patches = {}
    for _, ring in ipairs(rings) do layRing(position, ring, patches) end
    if #patches > 0 then
      ghostBox = {name = name, patches = patches, baseFacing = placing:facing() or 0, rotation = 0,
                  lastX = position:x(), lastY = position:y()}
    end
    return
  end
  local x, y = position:x(), position:y()
  if x and y and ((x ~= ghostBox.lastX) or (y ~= ghostBox.lastY)) then
    ghostBox.lastX, ghostBox.lastY = x, y
    -- patch:position() raises on ground that cannot be kept; the box is dropped and re-laid next frame.
    local ok = pcall(function()
      for _, patch in ipairs(ghostBox.patches) do
        if patch:exists() then patch:position(position) end
      end
    end)
    if not ok then return removeGhostBox() end
  end
  local facing = placing:facing()
  if facing then rotateBox(ghostBox, facing) end
end

-- ---------------------------------------------------------------- modes

local function leaveMode()
  if sweepTimer then sweepTimer:cancel() end
  if facingTimer then facingTimer:cancel() end
  sweepTimer, facingTimer = nil, nil
  removeGhostBox()
  local boxes = laidBoxes
  laidBoxes = {}
  for _, box in pairs(boxes) do removePatches(box) end
end

local function enterMode()
  if isOff() then return end
  sweep()
  followGhost()
  sweepTimer = hafen.timer():every(RESCAN_SECONDS, sweep)
  facingTimer = hafen.timer():every(FACING_SECONDS, correctFacing)
end

-- "ground" <-> "over" only re-dresses the patches in place; nothing is re-laid.
modeOption:on("Changed", function(mode)
  onNextStep(function()
    if isOff() then
      leaveMode()
    elseif sweepTimer then
      redress()
    else
      enterMode()
    end
    hafen.log():write("hitboxes: " .. mode)
  end)
end)

for _, option in ipairs({fillOption, opacityOption, borderOption, borderWidthOption}) do
  option:on("Changed", function() afterSettle(redress) end)
end

hafen.client():options():keybindings():on("cycle", function()
  local current = 1
  for index, mode in ipairs(MODES) do
    if mode == modeOption:value() then current = index end
  end
  modeOption:value(MODES[(current % #MODES) + 1])
end)

-- GobAdded fires before the object's first drawn frame.
hafen.event():on("GobAdded", function(gob)
  if not isOff() then considerGob(gob) end
end)

-- A patch anchored to a gob is removed with the gob; only the record goes.
hafen.event():on("GobRemoved", function(gob)
  laidBoxes[gob] = nil
end)

hafen.event():on("Update", function()
  if isOff() then return end
  followGhost()
end)

-- The mode is remembered across restarts; the sweep waits a step for the world to be up.
if not isOff() then onNextStep(enterMode) end
