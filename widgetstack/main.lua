-- widgetstack -- a WoW /framestack clone + a click-to-inspect widget inspector + the SELECTOR INSPECTOR
-- (spec 20, W2; spec 030 B2). The standing in-game harness for the W-series widget introspection: it shows the
-- live stack of widgets under the cursor, outlines the hovered one, and lets you CLICK any level (or any child
-- inside an inspector) to open a window with that widget's full details -- a browsable widget inspector, built
-- entirely in pure Lua over W1/W2.
--
-- W2 adds the two reads that find *what is under the cursor* -- the only pieces missing from W1's tree:
--   hafen.ui():mouse()   -> the pointer entity: :x()/:y() the cursor in root coords (public UI.mc), polled
--                         each frame; also :over()/:shift()/:ctrl()/:alt()/:grab() (unused here)
--   hafen.ui():hit(x, y) -> the DEEPEST Widget object under that point, or nil. It mirrors the engine's own
--                         pointer dispatch, so it resolves EXACTLY the widget a real click would hit --
--                         correct under SCROLL offsets and non-rectangular hit areas (a naive rect test
--                         is wrong there). Walk :parent() up from the hit for the full stack.
--   w:rootPos()        -> { x=, y= }   the widget's top-left in root coords, for the highlight box
--
-- 030.3 / 049.4 -- THE SELECTOR INSPECTOR (the bottom panel). A selector system without one is unusable: nobody
-- guesses a widget's role. For the hovered widget the panel shows its role (or an honest nil), its class, its OWN
-- [title=]/[text=] and its [res=], then the ANCHOR STEP -- the nearest enclosing window -- and then every selector
-- built from those parts that ACTUALLY matches it, most specific first, each with how many widgets it matches and
-- this one's index among them. The bottom line is ready to paste into `:lua`.
--   * 049.4 -- THE GRAMMAR IS CSS, so an attribute tests the widget its step is WRITTEN ON: [title=] is a WINDOW's
--     own caption (and is a parse error anywhere else), [text=] is the words any other widget displays. Reaching
--     the enclosing window is a step of its own in front, separated by a space: the descendant combinator. So the
--     panel builds CHAIN candidates (`window[title=Cupboard] button[text=Close]`), which is what names ONE widget
--     while two Cupboards are open.
--   * The operators come with it. [res=] is EXACT, so the panel offers [res*=<last path segment>] beside it -- the
--     contains form. And where a value has a stable stem before its first digit ("Hunger: 87%"), it offers
--     [text^=Hunger:], the form that keeps matching when the tail moves; the walk below decides which of the two
--     is actually true.
--   * The list is SELF-VALIDATING: each candidate is resolved with s:ui():matchAll() and kept only if the hovered
--     widget is in the result. So nothing is ever offered that does not resolve -- which is exactly the claim
--     the offered line makes. A candidate that does not even PARSE is dropped by the same pcall.
--   * `s:ui():match("sel")` is offered only where the candidate matches this widget and NOTHING else;
--     otherwise the line is `s:ui():matchAll("sel")[i]`, because match() refuses an ambiguous answer rather than
--     handing back whichever widget the walk met first. The offered line is the most specific candidate that
--     names it ALONE, falling back to the most specific of all -- a chain usually IS the one that names it alone.
--   * "*" is deliberately omitted: it matches every widget, so it says nothing and it is the one walk that
--     interns the whole tree.
--   * THE PRICE IS REPORTED: a chain candidate costs one more tree walk than the flat candidate it extends, so
--     the header line says how many walks the last rebuild cost and how many of them were chains.
-- Click any panel row (or run `:selector`) to LOG the line -- chat-log text is selectable, which is how it
-- leaves the client. Freeze first (the "freeze" hotkey), or moving the mouse to the window re-hovers.
--
-- THE EFFICIENCY GUARD (029.1: plain `==`): the poll fires EVERY frame, but the hovered widget only
-- changes when the mouse moves onto a different one. So we cache the last hovered leaf and BAIL EARLY when
-- it hasn't changed -- no tree walk, no selector resolution, no window rebuild, per frame. A per-rebuild
-- counter (and the number of selector walks it cost), shown in the window, does NOT tick while the cursor
-- sits still. Widget objects are INTERNED, so two lookups of the same live widget are the SAME value and
-- `==` IS the identity test -- :same() is gone with the collapse.
--
-- AND NOTHING RUNS WHILE THE WINDOW IS CLOSED. The poll is the window's OWN Update (see open()), so it
-- fires while the window stands and not once after it has gone -- the X and :widgetstack both destroy the
-- window, and the subscription goes with it -- and the outline overlay is added when the window opens and
-- removed when it closes. A closed widgetstack costs nothing a frame: no poll, no guard, no painter.
--
-- THE INSPECTOR: the stack rows are CLICKABLE -- click one and a new "Inspector" window opens with that
-- widget's type/id/pos/size/rootpos/visible/text + role/res + its selector + its parent link + its child
-- list. Inside an inspector, click a child (to descend) or the parent link (to ascend) to open a further
-- inspector window. Freeze the stack first (the "freeze" hotkey) so it holds still while you move the mouse
-- into the window to click a row. That hotkey starts UNBOUND: assign it under Options > Keybindings >
-- Widgetstack (suggested: Ctrl+Shift+F).
--
-- THE TREE COLUMN (the left-hand panel): the COMPLETE tree of the character on screen, as a treeview --
-- every widget the client has up for them, hidden or covered or not -- with nothing of the hover in it.
-- Live off two subscriptions on the tree (Added and Removed on "*"), expanded and collapsed row by row; a
-- click outlines the widget on the screen and a right click opens its Inspector. See "the tree column".
--
-- 063.4 -- WHAT IT ANSWERS. Under both of those sits the read block: everything the widget will answer about
-- ITSELF, driven off ONE table in ONE fixed order (see READS) so the hover panel and every Inspector window
-- print the same lines in the same places. A line appears only where the read answered something, so what
-- you are looking at is what the widget HAS -- see describe().

hafen.log():write("widgetstack loaded")

local win                 -- the floating stack window while it stands: open() builds it, the X or :widgetstack destroys it
local place               -- { x=, y= } where the window stood when it was last closed, so the next open() puts it back there
local last                -- the Widget object we last built the stack for (the guard's memory)
local rows = {}           -- the current stack, LEAF-FIRST: { {node,type,id,text,w,h}, ... }
local insp                -- the selector report for the hovered leaf (see selectorsFor)
local reads = {}          -- 063.4: the read block for the hovered leaf (see describe)
local hoverPos            -- { x=, y= } the hovered leaf's top-left in root coords (highlight box)
local hoverSize           -- { w=, h= } its size
local rebuilds = 0        -- how many times we rebuilt the stack (proves the `==` guard: it should NOT
                          -- climb while the cursor sits still)
local walks = 0           -- how many s:ui():matchAll() walks the last rebuild cost (the honest price of the panel)
local frozen = false      -- the "freeze" hotkey: hold the stack still so you can mouse into the window to read it

local LINE = 14                     -- row height, shared by every list here
local TREE_W = 340                  -- the tree column, the left-hand part of the window
local STACK_W = 580                 -- the stack's part beside it (049.4: a chain candidate is a long line)
local STACK_X0 = TREE_W             -- where the stack's part starts: every x of its draw is offset by this
local WIN_W, WIN_H = TREE_W + STACK_W, 574   -- 063.4: the height is the read block's
local STACK_Y0 = 22                 -- first stack row y (shared by draw + click hit-test)
local STACK_MAXROWS = 11            -- stack rows that fit above the selector panel

-- ============================================================== the selector inspector (030.3), shared by
-- the hover panel and each Inspector window. Pure Lua over w:role()/:type()/:res() + s:ui():matchAll().
--
-- A LOOKUP IS ADDRESSED AT A CHARACTER: the client's widgets stand in the tree of the session that put them
-- up, so every walk and every offered line goes through hafen.session():current() -- the one the pointer is
-- over. On the login screen there is none, and the panel simply offers nothing.

local SPELL = "hafen.session():current():ui()"     -- default fallback prefix for pasted selectors

local function find_top_root(widget_node)
  local current_node = widget_node
  while current_node and current_node:parent() do
    current_node = current_node:parent()
  end
  return current_node
end

local function resolve_spell_for_widget(target_widget)
  local target_root = find_top_root(target_widget)
  local current_session = hafen.session():current()
  if current_session and (current_session:ui():root() == target_root) then
    return "hafen.session():current():ui()", target_root
  end

  local session_list = hafen.session():list()
  for session_index = 1, #session_list do
    local active_session = session_list[session_index]
    local session_ui = active_session:ui()
    if session_ui and (session_ui:root() == target_root) then
      local account_user = active_session:user()
      if account_user then
        return ('hafen.session():get("%s"):ui()'):format(account_user), target_root
      end
    end
  end

  return "hafen.session():current():ui()", target_root
end

local function client_ui()
  local current_session = hafen.session():current()
  return current_session and current_session:ui()
end

local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

local function ellipsis(s, n) return (#s <= n) and s or (s:sub(1, n - 2) .. "..") end

-- A value goes into [key=value] EXACTLY as it was read. The parser trims whatever it finds between "=" and "]",
-- so a value with its own leading or trailing space could never match itself; one carrying "]" cannot be written
-- at all; an empty one is a parse error. None of the three is offered -- better no candidate than one built to be
-- thrown away by the walk below.
local function writable(s)
  if not s or s:find("]", 1, true) then return nil end
  if (s == "") or (s ~= trim(s)) then return nil end
  return s
end

-- The forms of ONE attribute key -- 049.1's operators, offered where they say something the exact form does not.
-- The exact form is brittle wherever the tail moves (a count, a percentage, a quantity), so where the value has a
-- stable stem before its first digit the ^= form is offered beside it, one weight below: less specific, but the
-- one still matching a second later. The walk decides which is true; a form that does not resolve is dropped.
-- (The stem IS trimmed, unlike an exact value: "Hunger: 87%" gives [text^=Hunger:], which the parser reads back
-- as written and which really is a prefix of the text.)
local function attrForms(key, val, wgt)
  local forms = { { s = ("[%s=%s]"):format(key, val), wgt = wgt } }
  local stem = val:match("^(%D-)%d")
  stem = stem and writable(trim(stem))
  if stem and (stem ~= val) then
    forms[#forms + 1] = { s = ("[%s^=%s]"):format(key, stem), wgt = wgt - 1 }
  end
  return forms
end

-- [res=] is EXACT (049.1): a selector that means a substring has to say so, because [res=<partial>] parses and
-- simply matches nothing. So the contains form is offered by name, on the last path segment.
local function resForms(res)
  local forms = { { s = ("[res=%s]"):format(res), wgt = 8 } }   -- the stable key (D-063): most specific
  local tail = writable(res:match("([^/]+)$"))
  if tail and (tail ~= res) then
    forms[#forms + 1] = { s = ("[res*=%s]"):format(tail), wgt = 6 }
  end
  return forms
end

-- THE ANCHOR STEP (049.4): the nearest enclosing window that has a caption to be named by, written as a step of
-- its own to go in FRONT of the target's, separated by a space. That is what tells two open Cupboards apart.
--   Strictly enclosing: a window's OWN caption is its own step's [title=], not a chain in front of itself. An
-- uncaptioned window is skipped rather than ending the search -- the space is descendant at ANY depth, so a
-- window further up still anchors the chain.
local function anchorStep(w)
  local n = w:parent()
  while n do
    if n:role() == "window" then
      local cap = writable(n:text())
      if cap then return { s = ("window[title=%s]"):format(cap), wgt = 5, cap = cap } end   -- role 1 + title 4
    end
    n = n:parent()
  end
  return nil
end

-- Enumerate every step a set of keys can write. Each grammar KEY contributes at most ONE refiner to a step --
-- "[res=x][res*=y]" is refused as "given more than once" -- so this is a mixed-radix counter over
-- (absent + each form), not a bitmask over parts. Keys are visited in the order the grammar wants them written:
-- role, then @Class, then the brackets. A key marked `req` has no absent slot.
local function stepCands(keys)
  local out, n = {}, 1
  for i = 1, #keys do n = n * (#keys[i].forms + (keys[i].req and 0 or 1)) end
  for code = 0, n - 1 do
    local c, s, score = code, "", 0
    for i = 1, #keys do
      local k = keys[i]
      local r = #k.forms + (k.req and 0 or 1)
      local pick = (c % r) + (k.req and 1 or 0)
      c = math.floor(c / r)
      if pick > 0 then
        s = s .. k.forms[pick].s
        score = score + k.forms[pick].wgt
      end
    end
    if s ~= "" then out[#out + 1] = { s = s, score = score } end
  end
  return out
end

-- The ready-to-paste line for one candidate. :match(sel) answers only where there IS one answer, so it is
-- offered only when this candidate matches this widget and NOTHING else; otherwise the index form is what actually
-- hands back this widget. Offering it for the first of several would hand the user a line that raises.
local function pasteLine(candidate, custom_spell)
  local spell_prefix = custom_spell or candidate.spell or (insp and insp.spell) or SPELL
  if candidate.count == 1 then
    return ('%s:match("%s")'):format(spell_prefix, candidate.sel)
  end
  return ('%s:matchAll("%s")[%d]'):format(spell_prefix, candidate.sel, candidate.idx)
end

-- The walk budget. Candidates are RANKED before a single walk is paid for, so what the cap drops is always the
-- least specific tail of the list -- never the line the panel is about to offer. It is a safety net rather than
-- a policy: the widest real widget (a role, a class, a text with a moving tail and a res) builds 36.
local MAXWALKS = 36

-- Build the selector report for `w`: its parts, its anchor, every candidate built from those that really matches
-- it (verified by resolving it), most-specific-first, and the one to offer. Costs one s:ui():matchAll() walk per
-- candidate walked -- which is why it runs on a hover CHANGE, never per frame, and why the count is reported.
local function selectorsFor(target_widget)
  local report = {
    role = target_widget:role(),
    cls = target_widget:type(),
    res = target_widget:res(),
    walks = 0,
    chains = 0,
    cands = {},
  }
  if report.cls == "?" then report.cls = nil end

  local spell_prefix, target_root = resolve_spell_for_widget(target_widget)
  report.spell = spell_prefix

  report.own = writable(target_widget:text())
  report.ownKey = (report.role == "window") and "title" or "text"

  local keys = {}
  if report.role then keys[#keys + 1] = { req = true, forms = { { s = report.role, wgt = 1 } } } end
  if report.cls then keys[#keys + 1] = { forms = { { s = "@" .. report.cls, wgt = 2 } } } end
  if report.own then keys[#keys + 1] = { forms = attrForms(report.ownKey, report.own, 4) } end
  local resource_value = writable(report.res)
  if resource_value then keys[#keys + 1] = { forms = resForms(resource_value) } end

  report.anchor = anchorStep(target_widget)

  local all_candidates = {}
  for step_index, step_candidate in ipairs(stepCands(keys)) do
    all_candidates[#all_candidates + 1] = { s = step_candidate.s, score = step_candidate.score, chain = false }
    if report.anchor then
      all_candidates[#all_candidates + 1] = {
        s = report.anchor.s .. " " .. step_candidate.s,
        score = step_candidate.score + report.anchor.wgt,
        chain = true,
      }
    end
  end
  table.sort(all_candidates, function(first_candidate, second_candidate)
    if first_candidate.score ~= second_candidate.score then
      return first_candidate.score > second_candidate.score
    end
    return #first_candidate.s < #second_candidate.s
  end)
  report.dropped = math.max(0, #all_candidates - MAXWALKS)

  for candidate_index = 1, math.min(#all_candidates, MAXWALKS) do
    local current_candidate = all_candidates[candidate_index]
    report.walks = report.walks + 1
    if current_candidate.chain then report.chains = report.chains + 1 end

    local success, hits = pcall(function()
      if target_root then
        return target_root:matchAll(current_candidate.s)
      elseif client_ui() then
        return client_ui():matchAll(current_candidate.s)
      end
      return nil
    end)

    if success and hits then
      local matched_index = nil
      for hit_index = 1, #hits do
        if hits[hit_index] == target_widget then
          matched_index = hit_index
          break
        end
      end
      if matched_index then
        report.cands[#report.cands + 1] = {
          sel = current_candidate.s,
          score = current_candidate.score,
          count = #hits,
          idx = matched_index,
          chain = current_candidate.chain,
          spell = spell_prefix,
        }
      end
    end
  end

  for candidate_index = 1, #report.cands do
    if report.cands[candidate_index].count == 1 then
      report.offer = report.cands[candidate_index]
      break
    end
  end
  report.offer = report.offer or report.cands[1]
  return report
end

-- ================================================================================ the read driver (063.4)
-- Everything a widget will answer about ITSELF, as ONE table in ONE fixed order -- shared by the hover panel
-- and by every Inspector window, so a line means the same thing and sits in the same place wherever you read
-- it. Each entry is { key, read, format }:
--   * the READ is pcall'ed, so a widget that refuses one still reports the other thirteen;
--   * the FORMAT turns the answer into the text of the line, and a format that produces NOTHING produces no
--     line. That is the whole gate. nil is silence, an empty collection is silence, and a plain `false` is
--     silence -- the block lists what the widget HAS, and a column of "nil" would say nothing at all about
--     the thing under the cursor while burying the two lines that do.
-- Seven of them -- :range() :rows() :rowHeight() :cellSize() :columns() :source() :image() -- read a control's
-- own adapter, which belongs to the addon that BUILT the control. They speak over a control of your own and
-- stay silent over the client's, which is the honest answer rather than a guess at one.
-- `owned` is w:info().owned: the provenance is a field of the snapshot, not a verb of its own.

local READ_MAXROWS = 8            -- lines the block draws before it says how many it clipped

local function faceName(v)
  return (type(v) == "string") and v or "(an asset of your own)"
end

-- The first `n` entries of an array, as text. A row may be a string or a {icon=, text=} table, and a column
-- descriptor a {title=, width=, of=} one, so each element is asked for the word it displays.
local function join(t, n)
  local parts = {}
  for i = 1, math.min(#t, n) do
    local v = t[i]
    parts[#parts + 1] = (type(v) == "table") and tostring(v.text or v.title or "?") or tostring(v)
  end
  if #t > n then parts[#parts + 1] = "..." end
  return table.concat(parts, ", ")
end

-- The keys a table actually carries, sorted -- a style's properties, a button's faces. `#` is 0 on all of
-- them: they are records, not arrays.
local function keysOf(t)
  local out = {}
  for k in pairs(t) do out[#out + 1] = tostring(k) end
  table.sort(out)
  return table.concat(out, ", ")
end

local function fmtHeld(v)         -- what a control HOLDS: a boolean, a number, a string, or a picked row
  if type(v) == "string" then return "'" .. v .. "'" end
  if type(v) == "table" then return v.text and ("'" .. tostring(v.text) .. "'") or "(a row)" end
  return tostring(v)
end

local READS = {
  { "picture",   function(w) return w:picture() end,   tostring },
  { "tooltip",   function(w) return w:tooltip() end,   function(v) return "'" .. v .. "'" end },
  { "value",     function(w) return w:value() end,     fmtHeld },
  { "range",     function(w) return w:range() end,     function(v) return ("%s..%s"):format(v.min, v.max) end },
  { "rows",      function(w) return w:rows() end,      function(v) return ("%d -- %s"):format(#v, join(v, 4)) end },
  { "rowHeight", function(w) return w:rowHeight() end, tostring },
  { "cellSize",  function(w) return w:cellSize() end,  function(v) return ("%dx%d"):format(v.w, v.h) end },
  { "columns",   function(w) return w:columns() end,   function(v) return ("%d -- %s"):format(#v, join(v, 4)) end },
  { "source",    function(w) return w:source() end,    faceName },
  { "image",     function(w) return w:image() end,
                 function(v) return ("up %s   [%s]"):format(faceName(v.up), keysOf(v)) end },
  { "items",     function(w) return w:items() end,
                 function(v) local count = v:count(); return (count > 0) and (count .. " inside") or nil end },
  { "focused",   function(w) return w:focused() end,
                 function(v) return v and "yes -- a keystroke reaches it" or nil end },
  { "owned",     function(w) local i = w:info(); return i and i.owned end,
                 function(v) return v and "yes -- this addon built it" or nil end },
  { "style",     function(w) return w:style() end,     function(v) return keysOf(v) end },
}

-- describe(w) -> the array of "key: value" lines, in the order above. Costs no tree walk of its own except
-- :items(), which traverses the widget's OWN subtree -- so it is built when the hover CHANGES and when an
-- Inspector opens, beside the selector report, and never per frame.
local function describe(w)
  local out = {}
  for i = 1, #READS do
    local r = READS[i]
    local ok, v = pcall(r[2], w)
    if ok and (v ~= nil) then
      local shown, s = pcall(r[3], v)
      if shown and s and (s ~= "") then
        out[#out + 1] = ellipsis(("%s: %s"):format(r[1], s), 60)
      end
    end
  end
  return out
end

-- The block, drawn identically in both windows: a divider, a header that says how many lines there are (or
-- that there are none), the lines, and the count of any it had to clip.
local function drawReads(g, x0, width, lines, headY, rowY)
  g:color(90, 90, 90); g:frect(x0 + 6, headY - 8, width - 12, 1); g:color()
  g:color(170, 170, 170)
  g:text((#lines == 0) and "it answers none of the widget reads"
                        or ("what it answers (%d):"):format(#lines), x0 + 6, headY)
  g:color()
  for i = 1, math.min(#lines, READ_MAXROWS) do
    g:text(lines[i], x0 + 10, rowY + (i - 1) * LINE)
  end
  if #lines > READ_MAXROWS then
    g:color(120, 120, 120)
    g:text(("... (+%d more)"):format(#lines - READ_MAXROWS), x0 + 10, rowY + READ_MAXROWS * LINE)
    g:color()
  end
end

-- ============================================================================================ the inspector

local openInspector       -- forward decl (it recurses: a child/parent click opens another inspector)
local openLater           -- ...and the same, one step later: opening one WALKS the inspected widget's tree
local inspCascade = 0     -- cascade new inspector windows so they don't land exactly on top of each other

-- Inspector layout constants (shared by its Draw + MouseDown handlers so a click maps to the same row it drew).
local I_W, I_H       = 470, 410       -- 049.4: wide enough for a chain candidate on one line
local I_ROLE_Y       = 62         -- role / res
local I_SEL_Y        = 76         -- the widget's selector (resolved ONCE, when the window opens)
local I_PARENT_Y     = 92         -- the clickable "parent" link row
local I_CHILD_Y0     = 122        -- first child row
local I_MAXROWS      = 8          -- children that fit above the read block (063.4)
local I_READ_HEAD    = 260        -- 063.4: the read block, on a band of its own so the click map above it
local I_READ_Y0      = 276        -- is the same arithmetic it always was

local function fmtCoord(c) return c and ("(" .. c.x .. "," .. c.y .. ")") or "-" end
local function fmtSize(c)  return c and (c.w .. "x" .. c.h) or "-" end

-- WHAT AN INSPECTOR SHOWS IS READ ON THE STEP. `:rootPos()` and `:children()` take the monitor of the tree
-- the widget stands in, and this window's Draw and its clicks are answered holding the LAYER's -- a second
-- tree, which no handler may take while it holds one (api/threading.md). So an inspector holds a SNAPSHOT,
-- re-taken every frame by the window's own Update where no tree is held, and the panel formats it. That is
-- the shape the stack window above has always had, and it is what makes a click on a child row reach the
-- widget the row was drawn from.
local function snap(st)
  local n = st.node
  if not n:exists() then
    st.live = {gone = true, kids = {}}    -- the widget went; the window stays, saying so
    return
  end
  local kids = {}
  for i, c in ipairs(n:children():list()) do
    kids[i] = {node = c, type = c:type() or "?", id = c:id(), text = c:text(), size = c:size()}
  end
  local p = n:parent()
  st.live = {
    id = n:id(), type = n:type() or "?", text = n:text(), visible = n:visible(),
    pos = n:position(), size = n:size(), rootpos = n:rootPos(),
    parent = p and {node = p, type = p:type() or "?", id = p:id()} or nil,
    kids = kids,
  }
end

openInspector = function(node)
  if not node then return end
  inspCascade = (inspCascade + 1) % 10
  -- Both of these are resolved ONCE, when the window opens: the selector costs a fistful of tree walks, and
  -- describe()'s :items() traverses this widget's own subtree. Everything else the window draws is read live.
  local st = { node = node, sel = selectorsFor(node), reads = describe(node) }
  local st_sel = st.sel
  snap(st)                     -- the first frame draws a snapshot like every frame after it

  st.win = hafen.ui():window()
    :title("Inspector: " .. (node:type() or "?"))
    :size(I_W, I_H)
    :position(480 + inspCascade * 22, 70 + inspCascade * 22)
  -- widget:on(key, fn) hands back a SUB, not the widget, so none of these can sit mid-chain (041.3) -- each is
  -- wired separately, after the builder chain above has finished configuring the window.
  st.win:on("Draw", function(ev)
      local g, w, h = ev:g(), ev:w(), ev:h()
      g:color(0, 0, 0, 175); g:frect(0, 0, w, h); g:color()
      local L = st.live
      -- header
      g:color(230, 230, 160)
      g:text(("%s%s%s"):format(L.type or "?",
             L.id and (" #" .. L.id) or "  (client-only, no :id)",
             L.gone and "   -- GONE" or ""), 6, 4)
      g:color()
      g:text(("visible: %s    pos: %s    size: %s")
        :format(tostring(L.visible), fmtCoord(L.pos), fmtSize(L.size)), 6, 20)
      g:text(("rootpos: %s"):format(fmtCoord(L.rootpos)), 6, 34)
      g:text(("text: %s"):format(L.text and ("'" .. L.text .. "'") or "(none)"), 6, 48)
      -- 030.3: what it IS in the selector vocabulary, and the selector that finds it again
      g:color(200, 200, 255)
      g:text(("role: %s    res: %s"):format(st_sel.role or "nil", st_sel.res or "-"), 6, I_ROLE_Y)
      g:color(150, 230, 150)
      g:text(st_sel.offer and ellipsis(pasteLine(st_sel.offer), 70) or "(no selector matches it)", 6, I_SEL_Y)
      g:color()
      -- parent link (clickable)
      local p = L.parent
      if p then
        g:color(150, 190, 255)
        g:text(("^ parent: %s%s  (click)"):format(p.type, p.id and (" #" .. p.id) or ""), 6, I_PARENT_Y)
      else
        g:color(120, 120, 120)
        g:text("^ parent: (this is the root)", 6, I_PARENT_Y)
      end
      g:color()
      -- children (each clickable to descend)
      local kids = L.kids
      g:text(("children (%d)  -- click one to descend:"):format(#kids), 6, I_PARENT_Y + LINE)
      for i = 1, math.min(#kids, I_MAXROWS) do
        local c = kids[i]
        g:color(180, 220, 180)
        g:text(("[%d] %s%s%s  %s"):format(
          i - 1, c.type,
          c.id and (" #" .. c.id) or "",
          c.text and (" '" .. c.text .. "'") or "",
          fmtSize(c.size)), 10, I_CHILD_Y0 + (i - 1) * LINE)
        g:color()
      end
      if #kids > I_MAXROWS then
        g:color(120, 120, 120)
        g:text(("... (+%d more)"):format(#kids - I_MAXROWS), 10, I_CHILD_Y0 + I_MAXROWS * LINE)
        g:color()
      end
      drawReads(g, 0, w, st.reads, I_READ_HEAD, I_READ_Y0)   -- 063.4: what this widget answers
      g:color(120, 120, 120); g:rect(0, 0, w, h); g:color()
  end)
  -- Re-read every frame the window stands, on the step, where no tree is held. The subscription is the
  -- window's own, so the X takes it with the window: nothing goes on being re-read for one that has gone.
  st.win:on("Update", function() snap(st) end)
  st.win:on("MouseDown", function(ev)
    local L = st.live
    local y = ev:y()
    if y >= I_SEL_Y and y < I_SEL_Y + LINE then                 -- the selector line: log it (copyable)
      if st_sel.offer then hafen.log():write(pasteLine(st_sel.offer)) end
    elseif y >= I_PARENT_Y and y < I_PARENT_Y + LINE then       -- parent link
      if L.parent then openLater(L.parent.node) end
    elseif y >= I_CHILD_Y0 and y < I_CHILD_Y0 + I_MAXROWS * LINE then   -- a child row (never the read block)
      local idx = math.floor((y - I_CHILD_Y0) / LINE) + 1       -- 1-based
      local c = (idx <= I_MAXROWS) and L.kids[idx]
      if c then openLater(c.node) end
    end
    ev:preventDefault()                                         -- consume (don't fall through)
  end)
end

-- Opening one walks the inspected widget's own tree -- selectorsFor() is a fistful of s:ui():matchAll()
-- calls and describe() reads its children -- so every click that opens one hands it to the step.
openLater = function(node)
  if node then hafen.timer():after(0, function() openInspector(node) end) end
end

-- ======================================================================================= the framestack HUD

-- Rebuild the stack from `last` up to the root, and re-resolve the selector panel. Only called on a HOVER
-- CHANGE (the guard gates it), so the expensive tree walks + window relayout happen once per change, not once
-- per frame. Each row keeps its NODE so a click can open that widget's inspector.
local function rebuild()
  rebuilds = rebuilds + 1
  local out = {}
  local n = last
  while n do
    local sz = n:size()
    out[#out + 1] = {
      node = n,                      -- the Widget object itself (for click-to-inspect)
      type = n:type() or "?",
      id   = n:id(),                 -- server id, or nil for a client-only widget
      text = n:text(),               -- best-effort, or nil
      w    = sz and sz.w or 0,
      h    = sz and sz.h or 0,
    }
    n = n:parent()
  end
  rows = out
  insp = last and selectorsFor(last) or nil     -- 030.3: the selector report for the hovered leaf
  reads = last and describe(last) or {}         -- 063.4: and everything that leaf answers about itself
  walks = insp and insp.walks or 0
  -- The highlight box tracks the leaf. Suppress it when the leaf is the root widget (hovering "nothing"
  -- resolves to the full-screen root -- faithful, but a whole-screen box is just noise), and over this
  -- addon's OWN windows -- the stack window and every Inspector -- where a box would only outline the
  -- panel being read. :owned() answers on the content and on the chrome around it, but the leaf under a
  -- close button is the button, so the whole stack is asked, leaf to root.
  local overOwn = false
  for index = 1, #out do
    if out[index].node:owned() then overOwn = true end
  end
  if last and (#out > 1) and not overOwn then
    hoverPos, hoverSize = last:rootPos(), last:size()
  else
    hoverPos, hoverSize = nil, nil
  end
end

-- The per-frame poll + the guard. This is the WoW-OnUpdate analog (the engine tick pump, 09) -- hung on
-- the stack window's own Update (see open()), so it runs on the step for every frame the window stands and
-- for none after it has gone.
local function poll()
  if frozen then return end                         -- held still: keep the last stack + box
  local m = hafen.ui():mouse()
  local mx, my = m:x(), m:y()
  if not mx then return end                          -- no UI yet
  local leaf = hafen.ui():hit(mx, my)                 -- deepest widget under the cursor (or nil)

  -- GUARD: same widget as last frame? -> bail (skip the rebuild entirely). This is the whole point, and it
  -- is what keeps the selector panel affordable: without it every frame would cost a fistful of tree walks.
  -- Interned entities (029.1), so `==` covers BOTH cases: same widget, and still hovering nothing (nil == nil).
  if leaf == last then return end
  last = leaf                                        -- hover CHANGED -> remember it and rebuild once
  rebuild()
end

-- ---- the selector panel (the bottom half of the stack window) --------------------------------------------

local PANEL_Y0  = STACK_Y0 + STACK_MAXROWS * LINE + 8   -- 184
local P_CLASS   = PANEL_Y0
local P_OWN     = PANEL_Y0 + LINE                        -- the widget's OWN [title=]/[text=] (049.1)
local P_RES     = PANEL_Y0 + 2 * LINE
local P_ANCHOR  = PANEL_Y0 + 3 * LINE                    -- 049.4: the chain's first step
local P_HEAD    = PANEL_Y0 + 60
local SEL_Y0    = PANEL_Y0 + 76
local SEL_MAXROWS = 7                                    -- role+class+[title=] is 7 combinations: it fits whole
local SEL_COUNT_X = 400                                  -- the right-hand "n matches, #i" column
-- 063.4: the read block, on a band of its own BELOW the offer line. The offer floats (see drawPanel), and
-- the lowest it can land is SEL_Y0 + 8*LINE + 8 = 380 -- so this band starts clear of it whatever the
-- candidate list came to, and the stack window's own click map above it is untouched.
local READ_HEAD = 406
local READ_Y0   = 422

local function drawPanel(g, w, h)
  g:color(90, 90, 90); g:frect(STACK_X0 + 6, PANEL_Y0 - 8, STACK_W - 12, 1); g:color()      -- divider
  if not insp then
    g:color(150, 150, 150); g:text("hover a widget to see what it IS and how to select it", STACK_X0 + 6, P_CLASS); g:color()
    return
  end
  g:color(230, 230, 160)
  g:text(("class: %s    role: %s"):format(insp.cls or "?", insp.role or "nil (nothing classifies it)"), STACK_X0 + 6, P_CLASS)
  g:color()
  -- Its OWN attribute, and it says WHICH key that is: since 049.1 a window is named by [title=] (its caption)
  -- and everything else by [text=] (the words it displays), and writing either on the other step is a parse error.
  g:text(("[%s=]  %s   (%s)"):format(
    insp.ownKey,
    insp.own and ("'" .. insp.own .. "'") or "-",
    (insp.ownKey == "title") and "its OWN caption" or "the words IT displays"), STACK_X0 + 6, P_OWN)
  g:text(("[res=]   %s"):format(insp.res or "-  (most windows carry no resource)"), STACK_X0 + 6, P_RES)
  -- The anchor step: the enclosing window, written in FRONT with a space. Not an attribute of this widget.
  g:color(180, 200, 255)
  g:text(("anchor:  %s   (%s)"):format(
    insp.anchor and ellipsis(insp.anchor.s, 44) or "-",
    insp.anchor and "the enclosing window: the chain's first step"
                 or "no captioned window encloses it: flat candidates only"), STACK_X0 + 6, P_ANCHOR)
  g:color()

  g:color(170, 170, 170)
  g:text(('selectors that match it, most specific first ("*" omitted):'), STACK_X0 + 6, P_HEAD)
  g:color()
  local n = #insp.cands
  for i = 1, math.min(n, SEL_MAXROWS) do
    local c = insp.cands[i]
    local y = SEL_Y0 + (i - 1) * LINE
    if c == insp.offer then g:color(150, 230, 150) end
    g:text(ellipsis(c.sel, 58), STACK_X0 + 10, y)              -- the count column starts at SEL_COUNT_X; do not run into it
    g:text(("%d match%s, #%d"):format(c.count, (c.count == 1) and "" or "es", c.idx), STACK_X0 + SEL_COUNT_X, y)
    if c == insp.offer then g:color() end
  end
  -- The offer FLOATS right under the list rather than sitting at a fixed y: most widgets have 3 candidates,
  -- and anchoring it to the bottom left the panel looking empty. Clicking anywhere below the rows still logs
  -- it, so nothing depends on where it lands.
  local used = math.min(n, SEL_MAXROWS)
  if n == 0 then
    g:color(200, 150, 150); g:text("(none -- it has no role, no named class and no key)", STACK_X0 + 10, SEL_Y0); g:color()
    used = 1
  elseif n > SEL_MAXROWS then
    g:color(120, 120, 120)
    g:text(("... (+%d less specific)"):format(n - SEL_MAXROWS), STACK_X0 + 10, SEL_Y0 + SEL_MAXROWS * LINE)
    g:color()
    used = used + 1
  end
  if insp.offer then
    g:color(150, 230, 150)
    g:text(pasteLine(insp.offer), STACK_X0 + 6, SEL_Y0 + used * LINE + 8)
    g:color()
  end
end

-- ======================================================================================= the tree column
--
-- THE LEFT-HAND PANEL: the COMPLETE tree of the character on screen, as a treeview -- every widget the
-- client has up for them, hidden or covered or not -- with nothing of the hover in it. Where the stack
-- answers "what is under the cursor", this answers "what is there at all": the zero-size, the hidden and
-- the covered widget a hover can never reach are all rows here.
--   * IT IS LIVE, and not by polling: two subscriptions on the tree -- s:ui():on("*", "Added") and its
--     "Removed" twin -- mark the rows dirty the moment a widget comes or goes, and they are rebuilt ONCE, on
--     the next step, however many arrived in the same tick. A slow beat (TREE_REFRESH) rebuilds them as
--     well, for what no event carries: a caption that changed, a widget hidden or shown.
--   * A rebuild walks the EXPANDED rows only, so it costs what is on show and never the whole tree. The
--     subscriptions are made while the window stands and dropped in close(): a closed window listens to
--     nothing, the rule this whole file keeps.
--   * [+] / [-] expands and collapses; the root starts open. A left click on a row PICKS it -- the row is
--     tinted and the widget is outlined on the screen in orange, which is how you tell which of forty
--     Labels this one is -- and a second click lets it go; a right click opens its Inspector.
--   * Draw reads none of it. A widget read takes its tree's monitor, which this window's Draw may not take
--     (api/threading.md), so the rows are built on the step and Draw formats what was built.

local TREE_X0       = 0                    -- the column is the left-hand part; a divider marks where it ends
local TREE_Y0       = STACK_Y0             -- first row y, level with the stack's
local TREE_INDENT   = 12                   -- pixels per depth
local TREE_MARKER_W = 22                   -- "[+]" and a gap, before the label
local TREE_MAXROWS  = math.floor((WIN_H - 20 - TREE_Y0) / LINE)   -- rows that fit above the footer line
local TREE_WHEEL    = 3                    -- rows per wheel notch
local TREE_REFRESH  = 0.5                  -- seconds between the beats that re-read the rows on show
local TREE_CHAR_W   = 6.7                  -- what a character of the default font is budgeted at, as elsewhere here

local session_subscriptions = {}
local event_subscriptions = {}
local expanded = {}
local tree_rows = {}
local tree_scroll = 0
local tree_pick = nil
local pick_position = nil
local pick_size = nil
local tree_dirty = true
local tree_clock = 0
local discovered_root_count = 0

local function sync_session_subscriptions(session_list)
  local active_set = {}
  for session_index = 1, #session_list do
    local active_session = session_list[session_index]
    active_set[active_session] = true
    if not session_subscriptions[active_session] then
      local session_ui = active_session:ui()
      if session_ui then
        session_subscriptions[active_session] = {
          session_ui:on("*", "Added", function()
            tree_dirty = true
          end),
          session_ui:on("*", "Removed", function(removed_widget)
            expanded[removed_widget] = nil
            if tree_pick == removed_widget then
              tree_pick = nil
            end
            tree_dirty = true
          end),
        }
      end
    end
  end

  for session_handle, subscriptions in pairs(session_subscriptions) do
    if not active_set[session_handle] then
      for subscription_index, subscription in ipairs(subscriptions) do
        subscription:off()
      end
      session_subscriptions[session_handle] = nil
    end
  end
end

local function reset_tree_subscriptions()
  for session_handle, subscriptions in pairs(session_subscriptions) do
    for subscription_index, subscription in ipairs(subscriptions) do
      subscription:off()
    end
  end
  session_subscriptions = {}

  for subscription_index, subscription in ipairs(event_subscriptions) do
    subscription:off()
  end
  event_subscriptions = {}
end

local function discover_roots()
  local roots = {}
  local seen_roots = {}

  local session_list = hafen.session():list()
  sync_session_subscriptions(session_list)

  for session_index = 1, #session_list do
    local active_session = session_list[session_index]
    local session_ui = active_session:ui()
    local session_root = session_ui and session_ui:root()
    if session_root and not seen_roots[session_root] then
      seen_roots[session_root] = true
      local character_name = active_session:character()
      local account_user = active_session:user()
      local label_tag = character_name or account_user or ("Session #" .. session_index)
      roots[#roots + 1] = {
        root = session_root,
        name = "Session: " .. label_tag,
        kind = "session",
        session = active_session,
      }
    end
  end

  if win then
    local layer_root = find_top_root(win)
    if layer_root and not seen_roots[layer_root] then
      seen_roots[layer_root] = true
      roots[#roots + 1] = {
        root = layer_root,
        name = "Addon Layer",
        kind = "layer",
        session = nil,
      }
    end
  end

  local probe_leaf = hafen.ui():hit(10, 10)
  if probe_leaf then
    local screen_root = find_top_root(probe_leaf)
    if screen_root and not seen_roots[screen_root] then
      seen_roots[screen_root] = true
      roots[#roots + 1] = {
        root = screen_root,
        name = "Screen UI",
        kind = "screen",
        session = nil,
      }
    end
  end

  return roots
end

local function tree_label(node, kids, open)
  local identifier = node:id()
  local text = node:text()
  local label = node:type() or "?"
  if identifier then label = label .. " #" .. identifier end
  if text then label = label .. " '" .. text .. "'" end
  if (kids > 0) and not open then label = label .. ("  (%d)"):format(kids) end
  return label
end

local function tree_walk(node, depth, out)
  local children = node:children():list()
  local child_count = #children
  local is_open = (expanded[node] == true) and (child_count > 0)
  out[#out + 1] = {
    node = node,
    depth = depth,
    kids = child_count,
    open = is_open,
    visible = node:visible(),
    label = tree_label(node, child_count, is_open),
  }
  if is_open then
    for child_index = 1, child_count do
      tree_walk(children[child_index], depth + 1, out)
    end
  end
end

local function rebuild_tree()
  local root_descriptors = discover_roots()
  discovered_root_count = #root_descriptors

  local out = {}
  for descriptor_index = 1, #root_descriptors do
    local descriptor = root_descriptors[descriptor_index]
    local root_node = descriptor.root
    local children = root_node:children():list()
    local child_count = #children

    if expanded[root_node] == nil then
      expanded[root_node] = true
    end
    local is_open = (expanded[root_node] == true) and (child_count > 0)

    out[#out + 1] = {
      node = root_node,
      depth = 0,
      kids = child_count,
      open = is_open,
      visible = root_node:visible(),
      label = ("%s [%s]%s"):format(
        root_node:type() or "RootWidget",
        descriptor.name,
        (child_count > 0 and not is_open) and ("  (%d)"):format(child_count) or ""
      ),
    }

    if is_open then
      for child_index = 1, child_count do
        tree_walk(children[child_index], 1, out)
      end
    end
  end

  tree_rows = out
  tree_scroll = math.max(0, math.min(tree_scroll, #out - TREE_MAXROWS))
end

local function tree_tick(delta_time)
  tree_clock = tree_clock + delta_time
  if tree_dirty or (tree_clock >= TREE_REFRESH) then
    tree_dirty = false
    tree_clock = 0
    rebuild_tree()
  end
  if tree_pick and tree_pick:exists() then
    pick_position, pick_size = tree_pick:rootPos(), tree_pick:size()
  else
    tree_pick, pick_position, pick_size = nil, nil, nil
  end
end

local function tree_scroll_by(amount_rows)
  tree_scroll = math.max(0, math.min(tree_scroll + amount_rows, #tree_rows - TREE_MAXROWS))
end

local function tree_row_at(y_coordinate)
  if y_coordinate < TREE_Y0 then return nil end
  local line_index = math.floor((y_coordinate - TREE_Y0) / LINE)
  if line_index >= TREE_MAXROWS then return nil end
  return tree_rows[tree_scroll + line_index + 1]
end

local function tree_click(event)
  local row = tree_row_at(event:y())
  if row then
    local marker_x0 = TREE_X0 + 6 + row.depth * TREE_INDENT
    local on_marker = (event:x() >= marker_x0) and (event:x() < marker_x0 + TREE_MARKER_W)
    if event:button() == 3 then
      openLater(row.node)
    elseif on_marker and (row.kids > 0) then
      expanded[row.node] = not row.open
      tree_dirty = true
    elseif tree_pick == row.node then
      tree_pick = nil
    else
      tree_pick = row.node
    end
  end
  event:preventDefault()
end

local function draw_tree(graphics, width, height)
  graphics:color(90, 90, 90)
  graphics:frect(STACK_X0, 6, 1, height - 12)
  graphics:color()
  local total_count = #tree_rows
  local shown_count = math.max(0, math.min(total_count - tree_scroll, TREE_MAXROWS))

  local header_text
  local current_session = hafen.session():current()
  local active_name = current_session and (current_session:character() or current_session:user())
  if active_name then
    header_text = ("tree (%d roots, active: %s, %d rows%s)"):format(
      discovered_root_count,
      active_name,
      total_count,
      (total_count > shown_count) and (", %d-%d"):format(tree_scroll + 1, tree_scroll + shown_count) or ""
    )
  else
    header_text = ("tree (%d roots, %d rows%s)"):format(
      discovered_root_count,
      total_count,
      (total_count > shown_count) and (", %d-%d"):format(tree_scroll + 1, tree_scroll + shown_count) or ""
    )
  end
  graphics:text(header_text, TREE_X0 + 6, 4)

  for line_index = 0, shown_count - 1 do
    local row = tree_rows[tree_scroll + line_index + 1]
    local y_position = TREE_Y0 + line_index * LINE
    local x_position = TREE_X0 + 6 + row.depth * TREE_INDENT
    local is_picked = (row.node == tree_pick)
    if is_picked then
      graphics:color(90, 65, 20, 200)
      graphics:frect(TREE_X0 + 2, y_position - 1, TREE_W - 4, LINE)
      graphics:color()
    end
    if row.kids > 0 then
      graphics:color(150, 190, 255)
      graphics:text(row.open and "[-]" or "[+]", x_position, y_position)
      graphics:color()
    end
    if is_picked then
      graphics:color(240, 190, 90)
    elseif not row.visible then
      graphics:color(120, 120, 120)
    end
    local max_characters = math.floor((TREE_W - 12 - row.depth * TREE_INDENT - TREE_MARKER_W) / TREE_CHAR_W)
    graphics:text(ellipsis(row.label, math.max(8, max_characters)), x_position + TREE_MARKER_W, y_position)
    graphics:color()
  end
  graphics:color(150, 150, 120)
  graphics:text("[+] opens / click outlines / right-click inspects", TREE_X0 + 6, height - 16)
  graphics:color()
end

-- ======================================================================================== the stack window

-- The window draws the stack text: root at the TOP, deeper widgets indented below (like /framestack).
-- Each row is CLICKABLE (see onClick) to open that widget's inspector.
local function drawStack(g, w, h)
  g:color(0, 0, 0, 160); g:frect(0, 0, w, h); g:color()            -- translucent backdrop
  local shown = math.min(#rows, STACK_MAXROWS)
  local above = #rows - shown                                      -- clipped at the ROOT end, never the leaf
  -- The price, reported (049.4): every candidate costs one tree walk, and a CHAIN candidate is one more than the
  -- flat one it extends. `+n unwalked` is the cap doing its job -- the ranking spent the budget on the top of the
  -- list, so what went unwalked is always the least specific tail.
  g:text(("under cursor  (rebuilds: %d, selector walks: %d (%d chain)%s%s%s)")
    :format(rebuilds, walks, insp and insp.chains or 0,
            (insp and (insp.dropped > 0)) and (", +" .. insp.dropped .. " unwalked") or "",
            (above > 0) and (", +" .. above .. " above") or "",
            frozen and ", FROZEN" or ""), STACK_X0 + 6, 4)
  if #rows == 0 then
    g:color(170, 170, 170); g:text("move the mouse over the UI", STACK_X0 + 6, STACK_Y0); g:color()
  else
    -- rows is leaf-first; draw shallowest-first (from index `shown` down to 1) so indent grows downward and
    -- the LEAF -- the widget the panel below is about -- is always the last line, never the clipped one.
    local y = STACK_Y0
    for i = shown, 1, -1 do
      local r = rows[i]
      local line = ("%s%s%s%s  %dx%d"):format(
        ("  "):rep(shown - i),
        r.type,
        r.id and (" #" .. r.id) or "",
        r.text and (" '" .. r.text .. "'") or "",
        r.w, r.h)
      -- tint the leaf (the hovered widget) so it stands out
      if i == 1 then g:color(120, 230, 120) end
      g:text(ellipsis(line, 62), STACK_X0 + 6, y)
      if i == 1 then g:color() end
      y = y + LINE
    end
  end
  drawPanel(g, w, h)
  drawReads(g, STACK_X0, STACK_W, reads, READ_HEAD, READ_Y0)        -- 063.4: what the hovered widget answers
  g:color(150, 150, 120)
  g:text("click a row to inspect / a selector to log it (the freeze hotkey holds it)", STACK_X0 + 6, h - 16)
  draw_tree(g, w, h)                                               -- the column to the left of all of that
  g:color(120, 120, 120); g:rect(0, 0, w, h); g:color()            -- 1px border
end

-- Map a click in the stack window to a row -> open that widget's inspector, or to a panel row -> LOG that
-- selector (the chat log is selectable, which is how a selector leaves the client). Displayed stack line k
-- (k=0 at the top) is at y = STACK_Y0 + k*LINE and corresponds to rows index i = shown - k (rows is
-- leaf-first, and only its deepest STACK_MAXROWS entries are drawn).
local function stackClick(ev)
  local y = ev:y()
  local shown = math.min(#rows, STACK_MAXROWS)
  if y >= STACK_Y0 and y < STACK_Y0 + shown * LINE and #rows > 0 then
    local k = math.floor((y - STACK_Y0) / LINE)
    local r = rows[shown - k]
    if r and r.node then openLater(r.node) end
  elseif y >= SEL_Y0 and y < READ_HEAD - 8 and insp then    -- the panel's own band: the read block is inert
    local k = math.floor((y - SEL_Y0) / LINE) + 1
    local c = insp.cands[k]
    if (k <= SEL_MAXROWS) and c then
      hafen.log():write(pasteLine(c))
    elseif insp.offer then
      hafen.log():write(pasteLine(insp.offer))
    end
  end
  ev:preventDefault()                                               -- consume
end

-- The HUD overlay draws the green highlight box over the hovered widget, in root coords (like WoW's outline),
-- and an orange one over the widget picked in the tree column.
local PICK_STROKE = 3           -- the picked widget's outline, in design pixels; g:rect is one hairline

-- A rectangle outlined with g:line at a stroke of its own, centred on the box's edge as g:rect's hairline
-- is; the horizontals run half a stroke past each side so the corners fill.
local function draw_thick_rect(graphics, x_coordinate, y_coordinate, rect_width, rect_height, stroke_width)
  local half_stroke = stroke_width / 2
  graphics:line(x_coordinate - half_stroke, y_coordinate, x_coordinate + rect_width + half_stroke, y_coordinate, stroke_width)
  graphics:line(x_coordinate - half_stroke, y_coordinate + rect_height, x_coordinate + rect_width + half_stroke, y_coordinate + rect_height, stroke_width)
  graphics:line(x_coordinate, y_coordinate, x_coordinate, y_coordinate + rect_height, stroke_width)
  graphics:line(x_coordinate + rect_width, y_coordinate, x_coordinate + rect_width, y_coordinate + rect_height, stroke_width)
end

local function draw_outline(graphics, width, height)
  if hoverPos and hoverSize then
    graphics:color(80, 230, 90)
    graphics:rect(hoverPos.x, hoverPos.y, hoverSize.w, hoverSize.h)
    graphics:color()
  end
  if pick_position and pick_size then
    graphics:color(240, 170, 60)
    draw_thick_rect(graphics, pick_position.x, pick_position.y, pick_size.w, pick_size.h, PICK_STROKE)
    graphics:color()
  end
end

-- The window has gone (the X) or is about to (:widgetstack): forget everything that was about it. Called
-- while it still stands -- Close fires before the client destroys the window, and the toggle calls this
-- before destroying it -- which is when its place can still be read, so the next open() puts it back there.
-- The outline goes with the window, and so do what was hovered and what the tree column listened to: a
-- closed window holds nothing still, hovers nothing and hears nothing.
local function close()
  place = win:position()
  win = nil
  hafen.ui():overlay():remove("outline")
  last, rows, insp, reads = nil, {}, nil, {}
  hoverPos, hoverSize = nil, nil
  frozen = false
  reset_tree_subscriptions()
  tree_pick, pick_position, pick_size = nil, nil, nil
  tree_rows = {}
  tree_scroll = 0
end

-- Build the window, and with it everything that runs only while it stands: the poll and the tree's beat,
-- as its own Update, and the outline overlay. All of it ends with it -- the Update because the subscription
-- is the window's, the overlay and the tree's subscriptions because close() drops them -- so a closed
-- widgetstack costs nothing a frame.
local function open()
  if win then return end
  tree_dirty = true                  -- the first step builds the column
  win = hafen.ui():window()
    :title("Widget Stack")
    :size(WIN_W, WIN_H)
    :position(place and place.x or 60, place and place.y or 60)
  -- widget:on(key, fn) hands back a SUB, not the widget (041.3), so none of these can sit mid-chain above.
  win:on("Draw", function(event) drawStack(event:g(), event:w(), event:h()) end)
  win:on("Update", function(delta_time)
    poll()
    tree_tick(delta_time)
  end)
  win:on("MouseDown", function(event)
    if event:x() < STACK_X0 then tree_click(event) else stackClick(event) end
  end)
  win:on("Wheel", function(event)
    if event:x() >= STACK_X0 then return end           -- over the stack's part the wheel is nobody's
    tree_scroll_by(((event:amount() > 0) and 1 or -1) * TREE_WHEEL)
    event:preventDefault()
  end)
  -- The chrome's close button destroys the window, so there is nothing left to hide: what is kept
  -- afterwards is "there is no window", and :widgetstack builds a new one where this one stood.
  win:on("Close", function()
    close()
    hafen.log():write("widgetstack: window closed (X) -- :widgetstack to bring it back")
  end)

  event_subscriptions[#event_subscriptions + 1] = hafen.event():on("SessionAdded", function(added_session)
    tree_dirty = true
  end)
  event_subscriptions[#event_subscriptions + 1] = hafen.event():on("SessionEnteredWorld", function(entered_session)
    tree_dirty = true
  end)
  event_subscriptions[#event_subscriptions + 1] = hafen.event():on("SessionSelected", function(selected_session)
    tree_dirty = true
  end)
  event_subscriptions[#event_subscriptions + 1] = hafen.event():on("SessionRemoved", function(removed_session)
    if session_subscriptions[removed_session] then
      for subscription_index, subscription in ipairs(session_subscriptions[removed_session]) do
        subscription:off()
      end
      session_subscriptions[removed_session] = nil
    end
    tree_dirty = true
  end)

  hafen.ui():overlay():add("outline"):draw(draw_outline)
  hafen.log():write("widgetstack: window up -- hover the UI; click a row to inspect; :selector logs the hovered widget's selector; :widgetstack toggles it, the freeze hotkey holds it")
end

-- :widgetstack -- toggle the window (WoW /framestack on/off): destroy it while it stands, build it when not.
hafen.console():on("widgetstack", function(args)
  -- The line is answered inside the CHARACTER's tree and the window stands in the layer, so the build and
  -- the destroy both go to the step, holding neither (api/threading.md).
  hafen.timer():after(0, function()
    if win then
      local standing = win
      close()                                       -- forget it while it still stands: its place is read there
      standing:destroy()
    else
      open()
    end
    hafen.log():write((":widgetstack -> window %s"):format(win and "opened" or "closed"))
  end)
end)

-- :selector -- log the hovered widget's full selector report. The window shows it too, but a logged line is
-- SELECTABLE, which is how the string actually gets out of the client and into your addon.
hafen.console():on("selector", function(args)
  if not insp then hafen.log():write(":selector -> nothing hovered (open the window with :widgetstack and move the mouse over the UI)"); return end
  hafen.log():write((":selector -> class=%s role=%s [%s=] %s res=%s anchor=%s")
    :format(insp.cls or "?", insp.role or "nil", insp.ownKey,
            insp.own and ("'" .. insp.own .. "'") or "-", insp.res or "-",
            insp.anchor and insp.anchor.s or "-"))
  hafen.log():write(("  (%d selector walks, %d of them chains%s)")
    :format(insp.walks, insp.chains, (insp.dropped > 0) and (", +" .. insp.dropped .. " unwalked") or ""))
  for i = 1, #insp.cands do
    local c = insp.cands[i]
    hafen.log():write(("  %s%s   (%d match%s, this one is #%d)")
      :format((c == insp.offer) and "* " or "  ", c.sel, c.count, (c.count == 1) and "" or "es", c.idx))
  end
  if insp.offer then hafen.log():write(pasteLine(insp.offer)) end
end)

-- "freeze" -- freeze/unfreeze the stack so you can move the mouse INTO the window to read + click it without
-- the stack changing under you. Declared through hafen.client():options():keybindings():on(name, fn); it
-- starts UNBOUND (D-047) -- assign it in Options > Keybindings > Widgetstack (suggested: Ctrl+Shift+F), where
-- the choice is persisted exactly like a built-in binding. Nothing to hold while no window stands.
hafen.client():options():keybindings():on("freeze", function()
  if not win then hafen.log():write(":widgetstack freeze -> no window up (:widgetstack opens it)"); return end
  frozen = not frozen
  hafen.log():write((":widgetstack freeze %s"):format(frozen and "ON" or "OFF"))
end)
