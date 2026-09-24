-- The tool window: a strip of six pencil cells and the eraser, the width slider with its caption and value,
-- and the Clear button.

local Brush = Paint.Brush
local Sheet = Paint.Sheet
local Stroke = Paint.Stroke

local Window = {}
Paint.Window = Window

-- Design pixels.
local PADDING = 6        -- from the content edge to everything in it
local GAP = 5            -- between two stacked controls
local CELL = 24          -- one tool cell of the strip
local CELL_GAP = 3       -- between two cells
local CAPTION_WIDTH = 40 -- the "Width"/"Rub" caption
local VALUE_WIDTH = 32   -- the number the slider shows

local STRIP_WIDTH = (CELL * Brush.TOOL_COUNT) + (CELL_GAP * (Brush.TOOL_COUNT - 1))
local WINDOW_WIDTH = STRIP_WIDTH + (PADDING * 2)
local SLIDER_WIDTH = WINDOW_WIDTH - (PADDING * 2) - CAPTION_WIDTH - VALUE_WIDTH - (GAP * 2)

local window, captionLabel, valueLabel

-- Whether the user has the window open. `window:visible()` is true from the moment the window is built.
Window.isOpen = false

local function updateCursor()
  local mouse = hafen.ui():mouse()
  if Brush.tool == nil then
    mouse:cursor(nil)
  elseif Brush.isEraser() then
    mouse:cursor("wrench")
  else
    mouse:cursor("dig")
  end
end

-- The slider's caption and value: "Width" under a pencil, "Rub" under the eraser.
local function refresh()
  if valueLabel then valueLabel:text(Brush.formatTenths(Brush.widthTenths)) end
  if captionLabel then captionLabel:text(Brush.isEraser() and "Rub" or "Width") end
end

-- Pick a tool, or put the picked one back.
local function pick(index)
  if Brush.tool == index then Brush.tool = nil else Brush.tool = index end
  if Brush.tool == nil then Stroke.finish() end
  updateCursor()
  refresh()
end

-- Put the picked tool down: the stroke ends, the cursor and the caption go back.
function Window.disarm()
  Brush.tool = nil
  Stroke.finish()
  updateCursor()
  refresh()
end

local function cellAt(x, y)
  if (y < 0) or (y >= CELL) then return nil end
  for index = 1, Brush.TOOL_COUNT do
    local cellX = (index - 1) * (CELL + CELL_GAP)
    if (x >= cellX) and (x < (cellX + CELL)) then return index end
  end
  return nil
end

local function drawStrip(graphics)
  for index = 1, Brush.TOOL_COUNT do
    local x = (index - 1) * (CELL + CELL_GAP)
    if index == Brush.ERASER then
      graphics:color(206, 206, 210, 255)
      graphics:frect(x, 0, CELL, CELL)
      graphics:color(90, 90, 96, 255)
      graphics:line(x + 5, CELL - 6, x + CELL - 6, 5, 2) -- the eraser's slash
    else
      local color = Brush.PENCILS[index].color
      graphics:color(color[1], color[2], color[3], 255)
      graphics:frect(x, 0, CELL, CELL)
    end
    graphics:color(24, 24, 26, 255)
    graphics:rect(x, 0, CELL, CELL)
    if Brush.tool == index then
      graphics:color(255, 255, 255, 255) -- a double ring inside the cell: a widget clips what leaves its box
      graphics:rect(x + 1, 1, CELL - 2, CELL - 2)
      graphics:rect(x + 2, 2, CELL - 4, CELL - 4)
    end
  end
  graphics:color()
end

-- A control whose art fixes its height (the slider, a button, a label) is given a width alone and its height
-- read back: `:size(width, height)` on one raises.
local function build()
  if window then return end
  window = hafen.ui():window():title(Paint.NAME)

  local strip = hafen.ui():widget():parent(window):position(PADDING, PADDING):size(STRIP_WIDTH, CELL)
  strip:name("tools")
  strip:on("Draw", function(event) drawStrip(event:g()) end)
  strip:on("MouseDown", function(event)
    local index = cellAt(event:x(), event:y())
    if index then pick(index) end
    event:preventDefault()
  end)

  local row = PADDING + CELL + GAP
  local slider = hafen.ui():slider():parent(window):size(SLIDER_WIDTH)
    :range(Brush.MIN_WIDTH_TENTHS, Brush.MAX_WIDTH_TENTHS):value(Brush.widthTenths)
  local sliderHeight = slider:size().h
  slider:position(PADDING + CAPTION_WIDTH + GAP, row)
  slider:on("Changed", function(event)
    Brush.widthTenths = event:value()
    refresh()
  end)

  captionLabel = hafen.ui():label():parent(window):text("Width")
  captionLabel:position(PADDING, row + math.floor((sliderHeight - captionLabel:size().h) / 2))
  valueLabel = hafen.ui():label():parent(window):text(Brush.formatTenths(Brush.widthTenths))
  valueLabel:position(PADDING + CAPTION_WIDTH + GAP + SLIDER_WIDTH + GAP,
                      row + math.floor((sliderHeight - valueLabel:size().h) / 2))

  row = row + sliderHeight + GAP
  local clearButton = hafen.ui():button():parent(window):size(64):text("Clear")
  clearButton:position(PADDING, row)
  clearButton:on("Pressed", function()
    hafen.timer():after(0, Sheet.clear) -- deferred: the press runs under the window's tree, not the ground's
  end)
  window:size(WINDOW_WIDTH, row + clearButton:size().h + PADDING)

  -- The chrome X hides the window rather than destroying it, so the menu button can show it again.
  window:on("Close", function(event)
    event:preventDefault()
    window:visible(false)
    Window.isOpen = false
    Window.disarm()
  end)
end

function Window.show(visible)
  build()
  window:visible(visible)
  Window.isOpen = visible
  if not visible then Window.disarm() end
end
