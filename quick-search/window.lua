-- The search field and the list of matches under it, built on every open and destroyed on close.

local Catalogue = QuickSearch.Catalogue

local Window = {}
QuickSearch.Window = Window

local WIDTH = 480          -- the field's width, and the list's, in design pixels
local FIELD_HEIGHT = 36
local PADDING = 10         -- a box's frame (gfx/hud/wnd corners, 8 px) and a little air
local BOX_GAP = 4          -- between the field's box and the list's
local ROW_HEIGHT = 24
local MAX_ROWS = 8         -- the list scrolls past this many
local ICON_SIZE = 20       -- the action's menu icon, scaled into a square this size
local ROW_PADDING = 6      -- the air at a row's ends and between its icon and its name

-- Both boxes wear the client's own window art: its background tiled under its frame. A theme naming
-- [name=quick-search/box] or [name=quick-search/results] beats this property by property.
local BOX_LOOK = {
  bg = {res = "gfx/hud/wnd/lg/bg", mode = "tile"},
  border = {box = "gfx/hud/wnd", mode = "tile"},
}

-- Neither the caption nor the close button has an "off". The button is put 200 px above the frame, where
-- the decoration's clip leaves nothing of it; the transparent bg hides the caption plate. The border is a
-- transparent line rather than none, since a border is what makes the rule own the frame instead of
-- leaving the stock art around the content.
local NO_CHROME = {
  bg = {color = {0, 0, 0, 0}},
  border = {color = {0, 0, 0, 0}, width = 1},
  closeButton = {at = "topleft", offset = {0, -200}},
}

-- The field's face. Its stock art is 20 px tall with end caps pinned to the top corners, so stretched to the
-- box it draws wrong: a flat fill and a line replace it. The 16 px text line matches the caret art, which is
-- 16 px tall and drawn from the top of the line.
local fieldFont = hafen.font():get("serif"):derive():size(16)
local FIELD_LOOK = {
  bg = {color = {0, 0, 0, 100}},
  border = {color = {196, 150, 70, 200}, width = 1},
}

-- A row: the action's name, and the categories it sits under (Craft > Food) at the right, smaller.
local nameFont = hafen.font():get("serif"):derive():size(14)
local pathFont = hafen.font():get("serif"):derive():size(11)
local NAME_COLOR = {235, 235, 235}
local PATH_COLOR = {170, 165, 150}
local HOVER_COLOR = {255, 255, 255, 40}
local MARK_COLOR = {196, 150, 70, 90}   -- the field's own gold, so the mark is not read as the pointer

local RESULTS_RULE = "[name=quick-search/results]"
local WINDOW_RULE = "[name=quick-search/window]"
local ARROW_KEYS = {previous = "Up", next = "Down"}

-- Where the field opens until the user drags it: the middle of the screen, kept there as the game window is
-- resized. A place the user dropped it at is put back by remember() in Window.open, a level above this rule.
local sheet = hafen.ui():sheet()
sheet:rule(WINDOW_RULE):anchor{to = "screen", at = "center"}
sheet:install()

local keybindings = hafen.client():options():keybindings()

local searchWindow = nil    -- the window holding the field, while open
local resultsBox = nil      -- the list's box, while open
local resultsList = nil     -- the widget the rows are drawn on, while open
local searchSession = nil   -- the character the open field searches
local rows = {}             -- the catalogue entries listed, in row order
local firstVisibleRow = 1   -- the row at the top of the list, moved by the wheel
local hoveredRow = nil      -- the row under the pointer
local markedRow = nil       -- the row the arrows marked; nil until one is pressed, and Enter takes the first
local arrowHotkeys = nil    -- the two arrow subscriptions, while open

-- ---------------------------------------------------------------- the arrow keys

-- Up and Down are the client's own camera zoom, and a hotkey holds its key off every other binding for as
-- long as its subscription lives. Taken as the field opens and dropped as it closes, so the arrows answer
-- the camera the rest of the time.
local function holdArrows()
  arrowHotkeys = {
    keybindings:on("previous", function()
      hafen.timer():after(0, Window.markPrevious)
    end),
    keybindings:on("next", function()
      hafen.timer():after(0, Window.markNext)
    end),
  }
  -- After the declaration, which is what mints the binding: a write on one nothing has declared raises. The
  -- key is written once, while the user has never touched that binding.
  for name, key in pairs(ARROW_KEYS) do
    local binding = keybindings:binding():get(name)
    if not binding:assigned() then
      binding:key(key)
    end
  end
end

local function releaseArrows()
  if arrowHotkeys == nil then
    return
  end
  for _, hotkey in ipairs(arrowHotkeys) do
    hotkey:off()
  end
  arrowHotkeys = nil
end

-- ---------------------------------------------------------------- open and close

function Window.isOpen()
  return searchWindow ~= nil
end

function Window.close()
  if searchWindow == nil then
    return
  end
  releaseArrows()
  resultsBox:destroy()
  resultsBox = nil
  resultsList = nil
  searchWindow:destroy()
  searchWindow = nil
  searchSession = nil
  sheet:rule(RESULTS_RULE):release()
  rows = {}
  firstVisibleRow = 1
  hoveredRow = nil
  markedRow = nil
end

-- Closed before the action runs: whatever the action raises then comes up over nothing of ours.
local function fire(entry)
  Window.close()
  if entry and entry.pagina:exists() then
    entry.pagina:use()
  end
end

-- ---------------------------------------------------------------- the list

-- The categories drawn at a row's right, cut to the room the name leaves: the outermost go first, behind an
-- ellipsis, so what stays is the end of the path, the part nearest the action. Measured once per entry, at
-- its first draw.
local function fittedPathFor(entry)
  if entry.fittedPath then
    return entry.fittedPath
  end
  local nameWidth = hafen.ui():measure(entry.name, {font = nameFont}).w
  local room = WIDTH - (ROW_PADDING + ICON_SIZE + ROW_PADDING + nameWidth + ROW_PADDING * 3)
  local names = {}
  for index, category in ipairs(entry.categories) do
    names[index] = category
  end
  local path = table.concat(names, " > ")
  while #names > 1 and hafen.ui():measure(path, {font = pathFont}).w > room do
    table.remove(names, 1)
    path = "… > " .. table.concat(names, " > ")
  end
  entry.fittedPath = path
  return path
end

-- The row under a point of the list, or nil.
local function rowAt(pointerY)
  local index = firstVisibleRow + math.floor(pointerY / ROW_HEIGHT)
  if pointerY < 0 or rows[index] == nil then
    return nil
  end
  return index
end

-- The list paints its rows itself: a listbox has no place for a second, smaller text at the right, and the
-- menu's own icons are not in the pool its icons load from. graphics:resource draws them from the game's.
local function drawRows(graphics, width, height)
  local roomForRows = math.floor(height / ROW_HEIGHT)
  for slot = 0, roomForRows - 1 do
    local index = firstVisibleRow + slot
    local row = rows[index]
    if row == nil then
      return
    end
    local top = slot * ROW_HEIGHT
    local middle = top + ROW_HEIGHT / 2
    if index == markedRow then
      graphics:color(MARK_COLOR)
      graphics:frect(0, top, width, ROW_HEIGHT)
      graphics:color()
    end
    if index == hoveredRow then
      graphics:color(HOVER_COLOR)
      graphics:frect(0, top, width, ROW_HEIGHT)
      graphics:color()
    end
    graphics:resource(row.resource, ROW_PADDING, top + (ROW_HEIGHT - ICON_SIZE) / 2, ICON_SIZE, ICON_SIZE)
    graphics:atext(row.name, ROW_PADDING + ICON_SIZE + ROW_PADDING, middle, 0, 0.5, {font = nameFont, color = NAME_COLOR})
    graphics:atext(fittedPathFor(row), width - ROW_PADDING, middle, 1, 0.5, {font = pathFont, color = PATH_COLOR})
  end
end

-- Move the mark by a row and scroll it into view. Nothing marked means the first row, the one Enter
-- already fires, so the first arrow puts the mark there rather than a row away from it.
local function moveMark(step)
  if #rows == 0 then
    return
  end
  if markedRow == nil then
    markedRow = 1
  else
    markedRow = math.min(#rows, math.max(1, markedRow + step))
  end
  if markedRow < firstVisibleRow then
    firstVisibleRow = markedRow
  elseif markedRow > firstVisibleRow + MAX_ROWS - 1 then
    firstVisibleRow = markedRow - MAX_ROWS + 1
  end
end

function Window.markPrevious()
  moveMark(-1)
end

function Window.markNext()
  moveMark(1)
end

-- A line for the console, without its colon: ":lo" is "lo". nil for a search.
local function commandOf(text)
  local line = text:match("^%s*:%s*(.-)%s*$")
  if line == nil or line == "" then
    return nil
  end
  return line
end

-- What the text asks for, and the list sized to it. A line for the console lists nothing.
local function showResults(text)
  local query = text:lower():match("^%s*(.-)%s*$")
  rows = {}
  if query ~= "" and text:match("^%s*:") == nil then
    rows = Catalogue.search(searchSession, query)
  end
  firstVisibleRow = 1
  hoveredRow = nil
  markedRow = nil

  local visibleRows = math.min(#rows, MAX_ROWS)
  if visibleRows == 0 then
    resultsBox:visible(false)
    return
  end
  local boxHeight = visibleRows * ROW_HEIGHT + PADDING * 2
  resultsList:size(WIDTH, visibleRows * ROW_HEIGHT)
  resultsBox:size(WIDTH + PADDING * 2, boxHeight)
  -- Hung under the window: the box's bottom edge on the window's, moved down by its own height and the gap.
  -- Said again at every size, since the offset carries the height.
  sheet:rule(RESULTS_RULE):anchor{to = searchWindow, at = "bottom", offset = {0, boxHeight + BOX_GAP}}
  resultsBox:visible(true)
end

-- ---------------------------------------------------------------- the field

-- A window takes the layer's keyboard as it is added, with no way to hand it the focus later, and it is
-- what answers Escape, through its own close. Its chrome is hidden and the panel inside it is what is seen.
function Window.open()
  local session = hafen.session():current()
  if session == nil or session:ui():match("@GameUI") == nil then
    return
  end
  Catalogue.ensure(session)
  searchSession = session
  holdArrows()

  -- Named, which is what the middle-of-the-screen rule points at. No :position here: a place written in
  -- pixels would stay put when the game window is resized.
  local boxWidth = WIDTH + PADDING * 2
  local boxHeight = FIELD_HEIGHT + PADDING * 2
  searchWindow = hafen.ui():window():name("window"):size(boxWidth, boxHeight)
  searchWindow:rule():bg(NO_CHROME.bg):border(NO_CHROME.border):closeButton(NO_CHROME.closeButton)

  -- The panel is added before the field so the field stands over it: the drag handle is offered only the
  -- press the field lets through.
  local panel = hafen.ui():widget():parent(searchWindow):name("box"):position(0, 0):size(boxWidth, boxHeight)
  panel:stock(BOX_LOOK)
  searchWindow:draggable(panel)

  -- Where the user last dropped it, one place for every character. The client keeps it relative to the
  -- screen, so it follows a resized game window or a new interface scale. After the size, so only a drag is
  -- saved.
  searchWindow:remember("field", hafen.store())

  local searchField = hafen.ui():entry():parent(searchWindow):position(PADDING, PADDING)
  searchField:size(WIDTH, FIELD_HEIGHT):value("")
  searchField:rule():font(fieldFont):bg(FIELD_LOOK.bg):border(FIELD_LOOK.border):padding(8, 0, 8, 0)

  resultsBox = hafen.ui():widget():name("results"):visible(false)
  resultsBox:stock(BOX_LOOK)
  resultsList = hafen.ui():widget():parent(resultsBox):position(PADDING, PADDING):size(WIDTH, ROW_HEIGHT)
  resultsList:on("Draw", function(event)
    drawRows(event:g(), event:w(), event:h())
  end)
  -- A move is handed to every widget, so the point may be outside the list.
  resultsList:on("MouseMove", function(event)
    local size = resultsList:size()
    local inside = event:x() >= 0 and event:x() < size.w and event:y() >= 0 and event:y() < size.h
    hoveredRow = inside and rowAt(event:y()) or nil
  end)
  resultsList:on("Wheel", function(event)
    local lastFirstRow = math.max(1, #rows - MAX_ROWS + 1)
    firstVisibleRow = math.min(lastFirstRow, math.max(1, firstVisibleRow + event:amount()))
    event:preventDefault()
  end)

  -- Escape is the window's own close: it fires Close and destroys the window when the handler returns, so
  -- the rest of the teardown goes on the next step.
  searchWindow:on("Close", function()
    hafen.timer():after(0, Window.close)
  end)

  -- A control's handler reaches its own tree alone; the menu and the console are the character's, so the
  -- work goes on the next step.
  searchField:on("Changed", function(text)
    hafen.timer():after(0, function()
      if searchWindow then
        showResults(text)
      end
    end)
  end)
  -- Enter: the command the line spells, else the marked action, else the first listed. A failing command is
  -- not the addon's error: its message goes to the character's System log.
  searchField:on("Submitted", function(text)
    hafen.timer():after(0, function()
      if searchWindow == nil then
        return
      end
      local command = commandOf(text)
      if command then
        Window.close()
        session:console():run(command)
      else
        fire(rows[markedRow or 1])
      end
    end)
  end)
  resultsList:on("MouseDown", function(event)
    local index = rowAt(event:y())
    event:preventDefault()
    if index == nil or event:button() ~= 1 then
      return
    end
    hafen.timer():after(0, function()
      if searchWindow then
        fire(rows[index])
      end
    end)
  end)
end
