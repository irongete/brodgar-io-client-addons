-- The three bar widgets: what each one draws, and the ALT drag that moves it.

local Config = HUD.Config
local Meters = HUD.Meters

local Bars = {}
HUD.Bars = Bars

local mouse = hafen.ui():mouse()

-- One face per size, built on first use. A font variant is writable only until something draws with it,
-- so a size change takes a new handle rather than a write to the one in hand.
local fontsBySize = {}

local function fontOfSize(size)
  local font = fontsBySize[size]
  if font == nil then
    font = hafen.font():get(Config.TEXT_FONT_FAMILY):derive():size(size)
    fontsBySize[size] = font
  end
  return font
end

local function colourFor(bar, segment)
  if bar.gameColourOption:value() then
    local published = segment:color()
    if published ~= nil then return published end
  end
  return {bar.redOption:value(), bar.greenOption:value(), bar.blueOption:value()}
end

local function clampFraction(value)
  if value == nil then return 0 end
  if value < 0 then return 0 end
  if value > 1 then return 1 end
  return value
end

-- A thickness that lands on the same number of device pixels on all four sides of a box. A design pixel
-- is not a whole device pixel on a scaled client and every rect is rounded on its own, so a thickness of
-- 1 at scale 1.5 draws two device pixels at the top and left and one at the bottom and right. Rounding
-- to whole device pixels first makes the four agree: round(box * scale - n) is round(box * scale) - n
-- exactly when n is whole.
local function deviceWholeThickness(designThickness)
  if designThickness <= 0 then return 0 end
  local scale = hafen.ui():scale() or 1
  if scale <= 0 then return designThickness end
  local devicePixels = math.floor((designThickness * scale) + 0.5)
  if devicePixels < 1 then devicePixels = 1 end
  return devicePixels / scale
end

-- One device pixel in design units: offsetting a draw by this much moves it exactly one pixel across at
-- any interface scale, where a flat 1 would be one and a half pixels at scale 1.5.
local function oneDevicePixel()
  local scale = hafen.ui():scale() or 1
  if scale <= 0 then return 1 end
  return 1 / scale
end

-- Four filled rectangles rather than graphics:rect(), whose line is one screen pixel however the client
-- is scaled: the thickness the user set is in design pixels and has to be drawn in them.
local function strokeBox(graphics, width, height, thickness)
  if thickness <= 0 then return end
  if ((thickness * 2) >= width) or ((thickness * 2) >= height) then
    graphics:frect(0, 0, width, height)                -- thicker than the box: the box is the border
    return
  end
  local inner = height - (thickness * 2)
  graphics:frect(0, 0, width, thickness)
  graphics:frect(0, height - thickness, width, thickness)
  graphics:frect(0, thickness, thickness, inner)
  graphics:frect(width - thickness, thickness, thickness, inner)
end

-- Held on the bar so the draw, which cannot reach the character's tree, has a figure to write.
local function refreshAmount(bar)
  local mode = bar.readingOption and bar.readingOption:value()
  if (mode ~= Config.READING_BOTH) and (mode ~= Config.READING_AMOUNT) then
    bar.amount = nil
    return
  end

  local session = hafen.session():current()
  bar.amount = session and Meters.statedAmount(session, bar)
end

local function readingText(bar, segments)
  local mode = bar.readingOption and bar.readingOption:value() or Config.READING_PERCENTAGE
  if mode == Config.READING_NOTHING then return nil end

  local first = segments[1]
  local percentage = first and ("%d%%"):format(math.floor((clampFraction(first:value()) * 100) + 0.5))
  if mode == Config.READING_PERCENTAGE then return percentage end

  local amount = bar.amount
  if mode == Config.READING_AMOUNT then return amount end
  if (percentage ~= nil) and (amount ~= nil) then return percentage .. " (" .. amount .. ")" end
  return percentage or amount                          -- a server that states no amount keeps the figure
end

local function drawBar(bar, drawEvent)
  local session = hafen.session():current()
  if session == nil then return end                    -- the login screen: nothing to report
  local meter = Meters.find(session, bar.resource)
  if meter == nil then return end                      -- the meters stream in a beat after the HUD

  local graphics = drawEvent:g()
  local width, height = drawEvent:w(), drawEvent:h()

  graphics:color(Config.TROUGH_COLOUR)
  graphics:frect(0, 0, width, height)

  -- Every segment from the left edge in the order the server sent them, as the client's own meter draws
  -- them: a later band paints over an earlier one and the widest is what shows.
  local segments = meter:segment():list()
  for _, segment in ipairs(segments) do
    local filled = math.ceil(width * clampFraction(segment:value()))
    if filled > 0 then
      graphics:color(colourFor(bar, segment))
      graphics:frect(0, 0, filled, height)
    end
  end

  -- A border of 0 is no border, but ALT still has to show what it is about to pick up, so the highlight
  -- is drawn at one pixel where the user asked for none.
  local thickness = bar.borderOption:value()
  if mouse:alt() then
    graphics:color(Config.HANDLE_COLOUR)
    strokeBox(graphics, width, height, deviceWholeThickness(math.max(thickness, 1)))
  else
    graphics:color(Config.BORDER_COLOUR)
    strokeBox(graphics, width, height, deviceWholeThickness(thickness))
  end

  local reading = readingText(bar, segments)
  local fontSize = bar.fontSizeOption:value()
  if (reading ~= nil) and (height >= (fontSize + Config.TEXT_ROOM)) then
    -- Both draws render the same string in the same face, so the anchored blit rounds them the same and
    -- the shadow stays exactly one pixel down and right of the line.
    local textFont = fontOfSize(fontSize)
    local shadowOffset = oneDevicePixel()
    graphics:color(Config.TEXT_SHADOW_COLOUR)
    graphics:atext(reading, (width / 2) + shadowOffset, (height / 2) + shadowOffset, 0.5, 0.5,
                   {font = textFont})
    graphics:color(Config.TEXT_COLOUR)
    graphics:atext(reading, width / 2, height / 2, 0.5, 0.5, {font = textFont})
  end

  graphics:color()
end

-- ---------------------------------------------------------------- ALT and a drag

-- widget:draggable(handle) would take the pointer on any press and swallow every click that landed on a
-- bar, so the gesture is taken by hand: a press with ALT down grabs, a press without it is not consumed
-- and falls through to the game underneath.
local activeDrag = nil                       -- {grab =, bar =, offsetX =, offsetY =}

local function endDrag()
  if activeDrag == nil then return end
  local bar = activeDrag.bar
  activeDrag.grab:release()
  activeDrag = nil
  local place = bar.widget:position()                  -- where it landed, the client's clamp included
  Config.rememberPlacement(bar, place.x, place.y)
end

local function beginDrag(bar, pressEvent)
  if activeDrag ~= nil then endDrag() end

  local grab = mouse:grab()
  if grab == nil then return end                       -- no layer to take the pointer in
  activeDrag = {
    grab    = grab,
    bar     = bar,
    offsetX = pressEvent:x(),                          -- where inside the bar the press landed
    offsetY = pressEvent:y(),
  }

  grab:on("Move", function(moveEvent)
    if activeDrag == nil then return end
    bar.widget:position(moveEvent:x() - activeDrag.offsetX, moveEvent:y() - activeDrag.offsetY)
  end)
  grab:on("Up", endDrag)
end

-- Drops the pointer without saving a place: for the teardown, where the widget is on its way out.
function Bars.releaseDrag()
  if activeDrag == nil then return end
  activeDrag.grab:release()
  activeDrag = nil
end

-- ---------------------------------------------------------------- the widgets

-- One widget per bar in the addon layer, which is drawn over the client's own windows.
function Bars.build()
  for _, bar in ipairs(Config.BARS) do
    local placement = Config.placementOf(bar)
    local widget = hafen.ui():widget()
      :name(bar.key)
      :size(bar.widthOption:value(), bar.heightOption:value())
      :position(placement and placement.x or Config.DEFAULT_X, placement and placement.y or bar.defaultY)
      :visible(Config.enabledOption:value())
    bar.widget = widget

    -- The options are read here rather than through a Changed handler on each, which would fire inside
    -- the Options window's tree and have to hop onto the step to reach the layer anyway.
    widget:on("Update", function()
      local shown = Config.enabledOption:value()
      if widget:visible() ~= shown then widget:visible(shown) end
      if not shown then return end
      local box = widget:size()
      local wantedWidth, wantedHeight = bar.widthOption:value(), bar.heightOption:value()
      if (box.w ~= wantedWidth) or (box.h ~= wantedHeight) then
        widget:size(wantedWidth, wantedHeight)
      end
      refreshAmount(bar)             -- the step is where the character's tree may be reached
    end)

    widget:on("Draw", function(drawEvent) drawBar(bar, drawEvent) end)

    widget:on("MouseDown", function(pressEvent)
      if (pressEvent:button() ~= 1) or (not mouse:alt()) then return end
      pressEvent:preventDefault()
      beginDrag(bar, pressEvent)
    end)
  end
end
