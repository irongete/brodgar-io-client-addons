-- The Options > AddOns > HUD page: Enable, and a section of settings per bar.

local Config = HUD.Config

local HEADING_FONT_SIZE = 14
local headingFont = hafen.font():get(Config.TEXT_FONT_FAMILY):derive():size(HEADING_FONT_SIZE)

local PANEL_GAP   = 6                                    -- between two cells of one row
local CELL_WIDTH  = 120                                  -- a row of three: the box and the colour
local PANEL_WIDTH = (CELL_WIDTH * 3) + (PANEL_GAP * 2)
local HALF_WIDTH  = (PANEL_WIDTH - PANEL_GAP) / 2        -- a row of two, over the same width

-- A cell of a row, as a column so its caption stands over its control.
--
-- The width is pinned: writing a label's text resizes the label to the words, an unpinned column takes
-- the width of its widest child, and that re-lays the row, the page and the settings window's scroll box.
-- Every step of a slider drag writes its caption, and a scroll box re-fitting under a live mouse grab
-- takes the thumb away from the pointer.
local function addCell(parentRow, cellWidth)
  return hafen.ui():column():gap(2):parent(parentRow):size(cellWidth)
end

-- A slider shows no number of its own, so its caption carries the value.
local function addSliderCell(parentRow, caption, option, tooltip, cellWidth)
  local cell = addCell(parentRow, cellWidth)
  local label = hafen.ui():label():parent(cell):text(caption .. ": " .. option:value())
  local slider = hafen.ui():slider():parent(cell):size(cellWidth):tooltip(tooltip):bind(option)
  slider:on("Changed", function(changed) label:text(caption .. ": " .. changed:value()) end)
  return cell
end

-- A dropdown shows its own value, so the caption is the heading alone.
local function addDropdownCell(parentRow, caption, option, tooltip, cellWidth)
  local cell = addCell(parentRow, cellWidth)
  hafen.ui():label():parent(cell):text(caption)
  hafen.ui():dropdown():parent(cell):size(cellWidth):tooltip(tooltip):bind(option)
  return cell
end

Config.options:panel(function(root)
  root:gap(4)

  hafen.ui():check():parent(root)
    :text("Enable")
    :tooltip("draw the three bars and hide the client's own health, stamina and energy meters")
    :bind(Config.enabledOption)
  hafen.ui():label():parent(root):text("Hold ALT and drag a bar to move it. Each one moves on its own.")

  for _, bar in ipairs(Config.BARS) do
    -- A separator is 5 design pixels of its own art: :size(width) leaves the height alone.
    hafen.ui():separator():parent(root):size(PANEL_WIDTH)
    -- The face goes on before the caption: writing the text is what measures the label and sizes it.
    local heading = hafen.ui():label():parent(root)
    heading:rule():font(headingFont)
    heading:text(bar.caption)

    local boxRow = hafen.ui():row():gap(PANEL_GAP):parent(root)
    addSliderCell(boxRow, "Width", bar.widthOption,
                  "how far the bar runs across the screen, in pixels", CELL_WIDTH)
    addSliderCell(boxRow, "Height", bar.heightOption,
                  "how tall the bar is, in pixels. A bar with less than " .. Config.TEXT_ROOM ..
                  " pixels over the font size below is too thin to carry the line, and it is left off",
                  CELL_WIDTH)
    addSliderCell(boxRow, "Border", bar.borderOption,
                  "how thick the line round the bar is, in pixels. 0 leaves the bar bare", CELL_WIDTH)

    -- The line the bar writes: what it says on the left, how big on the right. A bar with no choice of
    -- reading gives the whole row to the size.
    local textRow = hafen.ui():row():gap(PANEL_GAP):parent(root)
    if bar.readingOption ~= nil then
      addDropdownCell(textRow, "Reading", bar.readingOption,
                      "what the bar writes across itself: the percentage, the amount the server states " ..
                      "for it, both, or nothing at all", HALF_WIDTH)
    end
    addSliderCell(textRow, "Font size", bar.fontSizeOption,
                  "how big that line is set, in pixels. A bar with less than this much room over the " ..
                  "line leaves it off", HALF_WIDTH)

    local defaultColourCheck = hafen.ui():check():parent(root)
      :text("Default colour")
      :tooltip("paint the bar the colour the server publishes for it, the one the client's own meter " ..
               "uses. Untick to paint it the three sliders below instead")
      :bind(bar.gameColourOption)

    local colourRow = hafen.ui():row():gap(PANEL_GAP):parent(root)
    addSliderCell(colourRow, "R", bar.redOption, "red, 0 to 255", CELL_WIDTH)
    addSliderCell(colourRow, "G", bar.greenOption, "green, 0 to 255", CELL_WIDTH)
    addSliderCell(colourRow, "B", bar.blueOption, "blue, 0 to 255", CELL_WIDTH)

    -- The three sliders say nothing while the bar takes the game's colour. Disabling the row reaches
    -- every cell under it.
    colourRow:enabled(not bar.gameColourOption:value())
    defaultColourCheck:on("Changed", function(checked) colourRow:enabled(not checked) end)
  end
end)
