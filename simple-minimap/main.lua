-- Simple Minimap: the client's own corner minimap, moved into a panel of this addon's.
--
-- The CornerMap widget stays the client's -- clicks walk, the wheel zooms, icons and tooltips are its own --
-- and is re-parented into a bare hafen.ui():widget() of ours. Nothing here draws a map.
--
-- The panel is a frame around the map and nothing else. It is not a window: a window's decoration keeps a
-- caption band and a caption plate whether there is a caption or not, and a close button that would destroy
-- the map with it. A bare surface has none of that. Its look is a stock -- the client's own plain box over
-- the client's own window field -- that any rule naming [name=simple-minimap/map] beats, property by
-- property. A bare field of ours under everything else is its drag handle, so a press that neither the map
-- nor a button takes moves it, and a grip of ours in the bottom-right corner, drawn with the client's own
-- sizer, resizes it.
--
-- Above the map stands a row of the corner's own buttons: personal claims, village claims, provinces and icon
-- settings. They are the client's MenuCheckBox widgets, moved into the panel as the map is, so the tick, the
-- tooltip, the keybinding and what a press does stay the client's. The Map button is left in the corner: the
-- big map has its own key.
--
-- While it runs the client's corner is put away: the plate the map came out of and the panel with the
-- map/claim/icon buttons. They go as two whole panels because the fold arrows are the buttons' siblings, not
-- their children -- hiding the buttons alone would leave an arrow over an empty corner. Both come back on
-- Disable.

local EDGE = 8     -- the box's corners (gfx/hud/wnd, 32 px at scale 4): what the frame art needs
local PAD  = EDGE + 2   -- the frame and a little air: where the map and the row start
local MIN  = 64    -- a smaller map cannot be read
local GRIP = 25    -- the client's sizer, drawn by our grip in the panel's bottom-right corner

-- Each of the corner's buttons is one picture the size of the whole corner panel (416x272 at scale 4, so
-- 104x68 design px), transparent but for its own button, and the client routes a press by the picture's alpha.
-- The box is where that button lies in the picture; the widget is placed so the box lands in its slot, and the
-- rest of the picture hangs out of the row drawing nothing and taking no press.
local BUTTONS = {
  {picture = "gfx/hud/lbtn-claim", x = 1,  y = 14, w = 22, h = 21},   -- Display personal claims
  {picture = "gfx/hud/lbtn-vil",   x = 25, y = 23, w = 22, h = 21},   -- Display village claims
  {picture = "gfx/hud/lbtn-rlm",   x = 49, y = 25, w = 22, h = 21},   -- Display provinces
  {picture = "gfx/hud/lbtn-ico",   x = 32, y = 45, w = 22, h = 21},   -- Icon settings
}
local SLOT  = 22   -- one button's slot in the row
local GAP   = 2    -- the air between two slots
local ROW   = 24   -- the row's height, above the map: a button and a little air
local ROW_W = #BUTTONS * SLOT + (#BUTTONS - 1) * GAP
local MIN_W = math.max(MIN, ROW_W)   -- the map is never narrower than the row above it

local saved = hafen.store():var("state")   -- x, y: where the panel stands; w, h: the map's size

local dressed = {}   -- one record per character in the world: its map, its panel and the corner it came out of

-- Show or hide one of the corner's own panels. The write is refused when another addon already holds the
-- panel; the map is in our panel either way, so the refusal is left alone.
local function put(widget, shown)
  if widget and widget:exists() then
    pcall(function() widget:visible(shown) end)
  end
end

-- The panel's box for a map of this size, and back.
local function boxFor(width, height)
  return width + PAD * 2, height + PAD * 2 + ROW
end

local function mapIn(boxW, boxH)
  return math.max(MIN_W, boxW - PAD * 2), math.max(MIN, boxH - PAD * 2 - ROW)
end

-- ---------------------------------------------------------------- the panel

-- Every frame, on the step: the map fills the box the grip writes, the grip stays in the corner and the drag
-- field stays the panel's size. The resize gesture writes the panel's box with no event of ours until the
-- release, so it is read back here.
local function follow(record)
  local panel, map = record.panel, record.map
  if not (panel and panel:exists() and map and map:exists()) then return end
  local box = panel:size()
  local width, height = mapIn(box.w, box.h)
  local now = map:size()
  if now.w ~= width or now.h ~= height then map:size(width, height) end
  local grip = record.grip
  if grip and grip:exists() then
    local gripX, gripY = box.w - EDGE - GRIP, box.h - EDGE - GRIP
    local at = grip:position()
    if at.x ~= gripX or at.y ~= gripY then grip:position(gripX, gripY) end
  end
  local field = record.field
  if field and field:exists() then
    local fieldBox = field:size()
    if fieldBox.w ~= box.w or fieldBox.h ~= box.h then field:size(box.w, box.h) end
  end
end

-- The corner's buttons, by the picture each shows, in the row's order. A button the corner does not have (an
-- older client) is skipped and its slot left empty.
local function findButtons(session)
  local found = {}
  for _, candidate in ipairs(session:ui():matchAll("@MapMenu @MenuCheckBox")) do
    for index, spec in ipairs(BUTTONS) do
      if candidate:picture() == spec.picture then found[index] = candidate end
    end
  end
  return found
end

local function dress(record)
  if record.panel or not record.map:exists() then return end
  local box = record.map:size()
  local width, height = math.max(MIN_W, saved.w or box.w), math.max(MIN, saved.h or box.h)
  local boxW, boxH = boxFor(width, height)

  -- Built into the character's own tree: the map reads its session and would go dark in the addon layer.
  -- Named, which is what a theme's rule points at; the stock is what it looks like until one does.
  local panel = hafen.ui():widget():name("map"):parent(record.hud)
    :position(saved.x or 40, saved.y or 40):size(boxW, boxH)
  panel:stock{
    bg     = {res = "gfx/hud/wnd/lg/bg", mode = "tile"},
    border = {box = "gfx/hud/wnd", mode = "tile"},
  }
  record.panel = panel

  -- The drag handle: a bare surface the size of the panel, added FIRST so every later child stands over it.
  -- A handle's press is taken ahead of its own children (the gesture listens on the widget, before its
  -- mousedown walks them), so the panel itself as the handle would take the map's clicks and the buttons'
  -- too. As the lowest sibling the field is offered only what the map, a button and the grip let through.
  local field = hafen.ui():widget():parent(panel):position(0, 0):size(boxW, boxH)
  panel:draggable(field)
  record.field = field

  record.map:parent(panel):size(width, height):position(PAD, PAD + ROW)

  -- The row, after the map so a press is offered to a button first; off the button the picture is
  -- transparent, the client passes the press on, and the panel under it still drags.
  record.buttons = {}
  for index, button in pairs(findButtons(record.session)) do
    local spec = BUTTONS[index]
    local slotX = PAD + (index - 1) * (SLOT + GAP) + math.floor((SLOT - spec.w) / 2)
    local slotY = PAD + math.floor((ROW - spec.h) / 2)
    button:parent(panel):position(slotX - spec.x, slotY - spec.y)
    record.buttons[#record.buttons + 1] = button
  end

  -- The grip, last so it is offered a press before the map's corner under it. It draws the client's own
  -- sizer and resizes the panel; the map follows on the step.
  local grip = hafen.ui():widget():parent(panel):size(GRIP, GRIP)
    :position(boxW - EDGE - GRIP, boxH - EDGE - GRIP)
  grip:on("Draw", function(event) event:g():resource("gfx/hud/wnd/sizer", 0, 0) end)
  panel:resizable(grip)
  record.grip = grip

  put(record.cornerPanel, false)
  put(record.menuPanel, false)

  panel:on("Dragged", function(event)
    saved.x, saved.y = event:x(), event:y()
    hafen.store():flush()
  end)

  -- Once, on release: the floor is applied here rather than during the drag, where the gesture and this
  -- handler would take turns writing the size. The box that stands is the one saved.
  panel:on("Resized", function(event)
    local minW, minH = boxFor(MIN_W, MIN)
    local floorW, floorH = math.max(minW, event:w()), math.max(minH, event:h())
    if floorW ~= event:w() or floorH ~= event:h() then panel:size(floorW, floorH) end
    saved.w, saved.h = mapIn(floorW, floorH)
    hafen.store():flush()
  end)

  panel:on("Update", function() follow(record) end)
end

local function undress(record)
  if record.map and record.map:exists() then
    record.map:parent(nil)   -- home, whole: parent, order, place and box in one
  end
  for _, button in ipairs(record.buttons or {}) do
    if button:exists() then button:parent(nil) end   -- back into the corner's panel, stacked as the client had them
  end
  if record.panel and record.panel:exists() then
    record.panel:destroy()   -- the map and the buttons are out already; this takes the frame, the field and the grip, and ends the gesture
  end
  record.panel, record.field, record.grip, record.buttons = nil, nil, nil, nil
  put(record.cornerPanel, true)
  put(record.menuPanel, true)
end

-- ---------------------------------------------------------------- the characters

local function findRecord(session)
  for _, record in ipairs(dressed) do
    if record.session == session then return record end
  end
  return nil
end

-- One panel per character, because the map is one character's widget. The client destroys and re-makes the
-- CornerMap when the map file changes, and the watch fires for the map already up, so it is the whole wiring.
local function attach(session)
  if not session or findRecord(session) then return end
  local hud = session:ui():match("@GameUI")
  if not hud then return end
  local record = {session = session, hud = hud}
  dressed[#dressed + 1] = record
  session:ui():on("@CornerMap", "Added", function(map)
    if record.panel then undress(record) end   -- a rebuilt map: the old panel stood round a dead widget
    record.map = map
    record.cornerPanel = map:parent()          -- the panel it came out of: the plate and one arrow
    local menu = session:ui():match("@MapMenu")
    record.menuPanel = menu and menu:parent() or nil   -- the buttons and the other two arrows
    dress(record)
  end)
end

local function detach(session)
  for index, record in ipairs(dressed) do
    if record.session == session then
      table.remove(dressed, index)
      return
    end
  end
end

-- ---------------------------------------------------------------- lifecycle

hafen.event():on("SessionEnteredWorld", function(session) attach(session) end)
hafen.event():on("SessionRemoved", function(session) detach(session) end)

-- The engine restores what the addon holds, but the two corner panels have no toggle of their own: the rule is
-- "the widget ends up as the user was seeing it", and what they were seeing is this panel. Disable fires
-- before the teardown, so the corner is given back by hand.
hafen.event():on("Disable", function()
  for _, record in ipairs(dressed) do
    pcall(undress, record)
  end
  dressed = {}
end)
