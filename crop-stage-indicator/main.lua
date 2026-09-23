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

-- A crop whose resource is still resolving has no name yet and refuses the overlay; try again this often.
local RETRY_DELAY = 0.5
local RETRY_COUNT = 10

local showing = true

local function isCrop(gob)
  local resourceName = gob:name()
  return resourceName ~= nil and resourceName:sub(1, #CROP_PREFIX) == CROP_PREFIX and resourceName ~= TRELLIS
end

-- The stage is the first state byte the server sent with the crop (the one its resource picks the mesh
-- from), shown 1-based. Always an add, never just a relabel: add replaces the label on every session's copy
-- of the crop, so a copy that was still loading when the label first went on gets it too.
local function showStage(crop, retriesLeft)
  local stateBytes = crop:sdt()
  local stageIndex = stateBytes and stateBytes[1]
  if not stageIndex then return end
  local stageText = tostring(stageIndex + 1)
  local attached = crop:name() ~= nil and pcall(function()
    crop:overlay():add(OVERLAY_KEY):text(stageText):color(LABEL_COLOR):font(LABEL_FONT)
      :height(0):offset(0, LABEL_OFFSET_Y)
  end)
  if not attached and retriesLeft > 0 then
    hafen.timer():after(RETRY_DELAY, function()
      if showing and crop:exists() and (crop:name() == nil or isCrop(crop)) then
        showStage(crop, retriesLeft - 1)
      end
    end)
  end
end

local function showStages(session)
  for _, crop in ipairs(session:world():gob():list(isCrop)) do
    showStage(crop, RETRY_COUNT)
  end
end

-- A remove takes the label off every session's copy of the crop, but only through a session that still
-- holds it, and does nothing where there is no label. So every crop any session holds is asked: that reaches
-- every label, whichever session put it on. A crop no session holds has already lost its label.
local function hideStages()
  for _, session in ipairs(hafen.session():list()) do
    for _, crop in ipairs(session:world():gob():list(isCrop)) do
      crop:overlay():remove(OVERLAY_KEY)
    end
  end
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
-- are picked up here too. The event's gob is not tied to a session and reads nothing, so the crop is looked
-- up by id in the first session that holds it; the label goes on every session's copy from there.
hafen.event():on("GobSdtChanged", function(event)
  if not showing then return end
  local cropId = event:gob():id()
  for _, session in ipairs(hafen.session():list()) do
    local crop = session:world():gob():get(cropId)
    if crop:exists() then
      if crop:name() == nil or isCrop(crop) then showStage(crop, RETRY_COUNT) end
      return
    end
  end
end)

-- A character entering the world may load crops no other session has seen.
hafen.event():on("SessionEnteredWorld", function(session)
  if showing then showStages(session) end
end)
