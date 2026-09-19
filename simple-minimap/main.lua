-- Simple Minimap -- the client's own minimap, in a window of ours.
--
-- The client hangs its minimap in the bottom-left corner, inside a carved plate it blits over the map, in a
-- panel that cannot be moved and a box that cannot be sized. This addon TAKES that widget -- the same
-- CornerMap, still the client's -- into a window of its own, and then does what a window can do: stands
-- where you drag it by its title, sizes where you pull its corner, and wears whatever frame the client, or
-- a theme, gives its windows.
--
-- NOTHING HERE DRAWS A MAP. A click still walks you there, the wheel still zooms, the icons, the markers
-- and the tooltips are all still the client's. That is the whole point of taking the widget rather than
-- standing in for it: its picture is a render of the map database, and no addon could reproduce it.
--
--     window ┌─ Minimap ─────────────────── x ┐   <- the client's own frame, or a theme's window.frame
--            │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
--            │ ░┌──────────────────────────┐░ │
--            │ ░│         CornerMap        │░ │   <- the CLIENT's widget, taken in with widget:parent(win)
--            │ ░└──────────────────────────┘░ │
--            │ ░░░░░░░░░░░░░░░░░░░░░░░░░░░░ ◢ │   <- the client's own corner grip: window:resizable(true)
--            └────────────────────────────────┘
--
-- IT IS A WINDOW, NOT A SURFACE, AND THE CHROME IS WHAT THAT BUYS. A hafen.ui():widget() has no frame, so
-- a surface has to bring its own handles -- a strip to drag it by, a corner of its own to size it, a box
-- it declares for a theme to find. A window's frame already has all three: the caption drags it, the
-- corner grip sizes it, and the frame is the client's own art or a theme's `window.frame`. So there is
-- nothing here to dress and nothing a theme has to learn: `window[title=Minimap]` names it, as it names
-- any window.
--
-- THE GRIP DRIVES THE WINDOW, AND THE MAP FOLLOWS. The client's corner grip writes the window's content
-- box, so the map is kept the box's size less a margin from Update, live, and the floor is written once,
-- on release, in "Resized" -- during the drag the grip and a floor would take turns writing the size.
--
-- THE MARGIN IS FOR THE GRIP. The grip is a 25-px triangle in the content area's bottom-right corner,
-- drawn by the frame UNDER the content and offered a press AFTER it -- a map that reached the corner would
-- take every press meant for the grip and hide its glyph. PAD design px of the window's own field between
-- the map and the content box's edge, added to the frame's own margin outside it, leave the corner to the
-- grip: with the client's frame the whole triangle, with a theme's all but a sliver.
--
-- WHAT IS LEFT IN THE CORNER: NOTHING, AND IT IS THE TWO PANELS THAT SAY SO. The carved plate, the fold
-- arrows and the map/claim/icon buttons are not one widget and not one family -- the plate and one arrow
-- hang in the panel the map came out of, the buttons and two more arrows in the panel beside it. Hiding the
-- buttons alone leaves an arrow floating over an empty corner, because that arrow is their SIBLING and not
-- their child. So what is put away is the two panels themselves, which is legal precisely because the map
-- has already left the first one, and both are given back by hand when this stops.

local TITLE = "Minimap"             -- the caption: the handle you drag it by, and its name to a theme
local PAD   = 4                     -- the window's field between the map and the content box's edge
local MIN   = 64                    -- a map smaller than this is one you cannot read

local saved = hafen.store():var("state")
if saved.on == nil then saved.on = true end

local dressed = {}                  -- one record per character, each with that character's own map

-- THE STEP, AND NOT THE PRESS. The X's Close handler and a console line each run inside one character's
-- tree, and the other characters' windows stand in other trees, which no handler may take while it holds
-- one (api/threading.md). hafen.timer():after(0, fn) is the next step, holding none.
local function step(fn)
  hafen.timer():after(0, fn)
end

-- ---------------------------------------------------------------- the corner's own furniture

local function put(w, vis)
  if w and w:exists() then
    local ok, err = pcall(function() w:visible(vis) end)
    if not ok then hafen.log():write("Simple Minimap: " .. tostring(err)) end
  end
end

-- ---------------------------------------------------------------- on and off

-- Every frame, on the step: the map follows the box the grip writes, and where the caption drag left the
-- window is remembered. The title-bar drag is the client's own and fires nothing of ours, so it is read
-- back here -- against the place THIS window was last seen at, not against the saved one: two characters'
-- windows share the saved place but stand where each was dragged to -- and written to disk once, the frame
-- after it stops moving.
local function follow(r)
  if not (r.panel and r.panel:exists() and r.mmap and r.mmap:exists()) then return end
  local box = r.panel:size()
  local w, h = math.max(MIN, box.w - PAD * 2), math.max(MIN, box.h - PAD * 2)
  local now = r.mmap:size()
  if (now.w ~= w) or (now.h ~= h) then r.mmap:size(w, h) end
  local at = r.panel:position()
  if (not r.at) or (at.x ~= r.at.x) or (at.y ~= r.at.y) then
    local moved = r.at ~= nil
    r.at = at
    if moved then
      saved.x, saved.y = at.x, at.y
      r.moving = true
    end
  elseif r.moving then
    r.moving = false
    hafen.store():flush()
  end
end

local turn                          -- on or off, for every character -- below, after undress

local function dress(r)
  if r.panel or not r.mmap:exists() then return end

  local b = r.mmap:size()
  local w = math.max(MIN, saved.w or b.w)
  local h = math.max(MIN, saved.h or b.h)

  -- Built into the character's OWN tree: the map reads its session, so a window in the addon layer is
  -- refused as a destination -- and rightly, the widget would go dark there.
  r.panel = hafen.ui():window():title(TITLE):parent(r.hud)
                               :position(saved.x or 40, saved.y or 40):size(w + PAD * 2, h + PAD * 2)
  r.panel:resizable(true)           -- the client's own corner grip, drawn by the frame; a theme's `sizer` dresses it

  r.mmap:parent(r.panel):size(w, h):position(PAD, PAD)

  -- The corner's two panels go away whole -- see the note at the top: an arrow is the buttons' sibling.
  put(r.bl, false)
  put(r.menuPanel, false)

  -- Once, on release: the floor is written here and not during the drag, where the grip and this handler
  -- would take turns writing the size. The box that stands is the one that is saved.
  r.panel:on("Resized", function(ev)
    local bw, bh = math.max(MIN + PAD * 2, ev:w()), math.max(MIN + PAD * 2, ev:h())
    if (bw ~= ev:w()) or (bh ~= ev:h()) then r.panel:size(bw, bh) end
    saved.w, saved.h = bw - PAD * 2, bh - PAD * 2
    hafen.store():flush()
  end)

  -- The X -- and Escape while the window has the focus, which is the same door on any window -- means what
  -- `:simpleminimap` means: the corner is the client's again, until the next `:simpleminimap`. The client
  -- would destroy the window with the map still inside it; cancelled, it stands until the step undresses it.
  r.panel:on("Close", function(ev)
    ev:preventDefault()
    step(function() turn(false) end)
  end)

  r.panel:on("Update", function() follow(r) end)
end

local function undress(r)
  if r.mmap and r.mmap:exists() then
    r.mmap:parent(nil)                           -- home, whole: parent, order, place and box in one
  end
  if r.panel and r.panel:exists() then
    r.panel:destroy()                            -- the map is out already; this takes the window and its frame
  end
  r.panel, r.at, r.moving = nil, nil, nil
  put(r.bl, true)                                  -- ...and the corner is the client's again, whole
  put(r.menuPanel, true)
end

turn = function(on)
  saved.on = on
  hafen.store():flush()
  for _, r in ipairs(dressed) do
    if on then dress(r) else undress(r) end
  end
  hafen.log():write("Simple Minimap: " .. (on and "on, the map is in its own window"
                                              or "off, the client's corner is back"))
end

-- ---------------------------------------------------------------- the characters

local function record(s)
  for _, r in ipairs(dressed) do
    if r.s == s then return r end
  end
  return nil
end

-- One window per character, because the map is one character's widget. The subscription is what handles
-- the client REBUILDING its own map -- it destroys and re-makes the CornerMap when the map file changes --
-- and it fires at once for the map that is already up, so it is the whole of the wiring.
local function attach(s)
  if (not s) or record(s) then return end
  local hud = s:ui():match("@GameUI")
  if not hud then return end
  local r = {s = s, hud = hud}
  dressed[#dressed + 1] = r
  s:ui():on("@CornerMap", "Added", function(mmap)
    if r.panel then undress(r) end                -- a rebuilt map: the old window stood round a dead widget
    r.mmap = mmap
    r.bl = mmap:parent()                          -- the panel it came out of: the plate and one arrow are in it
    local menu = s:ui():match("@MapMenu")
    r.menuPanel = menu and menu:parent() or nil   -- ...and the buttons and two more arrows are in that one
    if saved.on then dress(r) end
  end)
end

local function detach(s)
  for i, r in ipairs(dressed) do
    if r.s == s then table.remove(dressed, i) return end
  end
end

-- ---------------------------------------------------------------- lifecycle

hafen.event():on("SessionEnteredWorld", function(s) attach(s) end)
hafen.event():on("SessionRemoved", function(s) detach(s) end)

-- GIVE THE CORNER BACK BY HAND. The engine restores everything this addon holds on its own, but the plate
-- and the buttons are not windows with a toggle: teardown's rule is "the widget ends up as the user was
-- seeing it", and what they were seeing is this window. Disable fires BEFORE the teardown, which is the
-- moment to say that what they should see now is the client's own corner.
hafen.event():on("Disable", function()
  for _, r in ipairs(dressed) do
    pcall(function() undress(r) end)
  end
  dressed = {}
end)

hafen.console():on("simpleminimap", function(args)
  -- `:simpleminimap diag` -- every Hidepanel this character has, whether it is on screen, and what is in
  -- it. Two of them are this addon's business and five are nobody's; the list says which is which.
  if args and (args[1] == "diag") then
    local s = hafen.session():current()
    if not s then hafen.log():write("Simple Minimap: no character on screen") return end
    for _, p in ipairs(s:ui():matchAll("@Hidepanel")) do
      local kids = {}
      for _, c in ipairs(p:children():list()) do kids[#kids + 1] = c:type() end
      local at, b = p:position(), p:size()
      hafen.log():write(("Simple Minimap: %s panel at %d,%d %dx%d [%s]"):format(
        p:visible() and "shown " or "HIDDEN", at.x, at.y, b.w, b.h, table.concat(kids, " ")))
    end
    return
  end

  -- The line is answered inside one character's tree and the windows stand in every character's, so the
  -- turn goes to the step, holding none.
  step(function() turn(not saved.on) end)
end)
