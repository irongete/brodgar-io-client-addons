-- Crop Stage Indicator: shows the growth stage number over every crop in view, at ground level.
-- Toggled with the hotkey assigned in Options > Game > Keybindings > Crop Stage Indicator.

local CROP_PREFIX = "gfx/terobjs/plants/"
local TRELLIS = "gfx/terobjs/plants/trellis"   -- under the crop path, but a frame for vines, not a crop

local OVERLAY_KEY = "stage"

-- Bold with a black outline so white reads over pale soil and dark leaves alike.
local LABEL_FONT = hafen.font():get("sans"):derive():size(11):bold(true):outline{0, 0, 0}
local LABEL_COLOR = {255, 255, 255}
-- A label is bottom-centred on its point; half a digit down puts the number's middle on the ground point.
local LABEL_OFFSET_Y = math.floor(hafen.ui():measure("8", {font = LABEL_FONT}).h / 2)

local showing = false
local labelledCrops = {}   -- [Gob] = true while our label is on it

local function isCrop(gob)
  local resourceName = gob:name()
  return resourceName ~= nil and resourceName:sub(1, #CROP_PREFIX) == CROP_PREFIX and resourceName ~= TRELLIS
end

-- The stage is the first state byte the server sent with the crop (the one its resource picks the mesh
-- from), shown 1-based. A crop whose resource is still resolving refuses the overlay, so retry once.
local function showStage(crop, retried)
  local stateBytes = crop:sdt()
  local stageIndex = stateBytes and stateBytes[1]
  if not stageIndex then return end
  local stageText = tostring(stageIndex + 1)
  local existingLabel = crop:overlay():get(OVERLAY_KEY)
  if existingLabel then
    existingLabel:text(stageText)
    return
  end
  local attached = pcall(function()
    crop:overlay():add(OVERLAY_KEY):text(stageText):color(LABEL_COLOR):font(LABEL_FONT)
      :height(0):offset(0, LABEL_OFFSET_Y)
  end)
  if attached then
    labelledCrops[crop] = true
  elseif not retried then
    hafen.timer():after(0.5, function()
      if showing and crop:exists() then showStage(crop, true) end
    end)
  end
end

local function showStages(session)
  for _, crop in ipairs(session:world():gob():list(isCrop)) do
    showStage(crop)
  end
end

-- The label hangs on the gob itself, so one remove clears it for every session.
local function hideStages()
  for crop in pairs(labelledCrops) do
    crop:overlay():remove(OVERLAY_KEY)
  end
  labelledCrops = {}
end

hafen.client():options():keybindings():on("toggle", function()
  showing = not showing
  if not showing then
    hideStages()
    return
  end
  for _, session in ipairs(hafen.session():list()) do
    showStages(session)
  end
end)

-- Fires for a crop advancing a stage and for the first state a crop is given, so crops coming into view
-- are picked up here too.
hafen.event():on("GobSdtChanged", function(event)
  local crop = event:gob()
  if showing and isCrop(crop) then showStage(crop) end
end)

-- The label went with the gob; only the bookkeeping is left.
hafen.event():on("GobRemoved", function(gob)
  labelledCrops[gob] = nil
end)

-- A character entering the world may load crops no other session has seen.
hafen.event():on("SessionEnteredWorld", function(session)
  if showing then showStages(session) end
end)
