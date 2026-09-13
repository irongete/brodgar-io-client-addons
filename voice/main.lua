-- Voice: proximity voice over voice.brodgar.io.
--
-- One link, held for the client's life: opened when the first character enters the world, following the
-- screen from then on, reconnected after a pause that doubles up to a minute when the server ends it or it
-- fails, and closed by the "Voice on" option. Every setting is on its page, Options ▸ AddOns ▸ Voice, and
-- three hotkeys — talk, mute, deafen — start unbound; the README suggests keys. Everything the link says
-- is one log line: "[voice] open, session N", "[voice] closed: <reason>", "[voice] error: <text>",
-- "[voice] reconnecting in N s". Who is talking is drawn over heads: a speaker over your own character
-- while your voice goes out, one over a peer while theirs arrives, and a struck one over a peer you muted.
-- :voice opens and closes the Voice window -- the link's state, a mute and a deafen, and a row per peer --
-- and a ring opened on another player takes a "Mute voice" / "Unmute voice" petal.

local SERVER = "wss://voice.brodgar.io"
local MIN_DELAY, MAX_DELAY = 2, 60      -- seconds between a lost link and the next try, doubling
local POLL = 0.05                       -- seconds between reads of the talk key while it is held

local opts = hafen.client():options():addon()

local voiceOn   = opts:boolean("on"):default(true):add()
local mode      = opts:choice("mode"):choices{"push to talk", "voice detection", "open mic"}
                    :default("push to talk"):add()
local threshold = opts:number("threshold"):range(0, 2000):default(350):add()
local agc       = opts:boolean("agc"):default(true):add()
local spatial   = opts:boolean("spatial"):default(true):add()
local volume    = opts:number("volume"):range(0, 400):default(100):add()     -- hundredths of the link's gain
local bitrate   = opts:number("bitrate"):range(8000, 64000):default(24000):add()

local function log(s) hafen.log():write("[voice] " .. s) end

-- THE LINK. `link` is the Voice handle from the moment it is built to the moment its Close or Error has
-- run, and nil between; `retry` is the timer armed for the next try, `delay` how long that is; `pending`
-- says the link now closing is to be replaced the instant it has ended — a connect-time setting moved, or
-- the option was turned back on before the close it asked for had run.
local link, retry, pending
local delay = MIN_DELAY
local muted, deafened = false, false    -- the toggles, kept here so a reconnect carries them over
local talking = false                   -- the talk key is held: the mode's own gate is set aside

-- THE PAINTERS. One overlay, keyed "voice", on every gob that has a voice: the character the link speaks
-- for, reading link:speaking(), and each peer, reading its own speaking() and muted(). The painter reads
-- the level on every frame, so no handler keeps a copy of it; what the handlers do is attach and remove.
-- A peer's gob may not exist yet when PeerAdded fires, or its own drawing may still be resolving, so a
-- sweep every second attaches what the moment could not, and the ending takes every one off.
local SWEEP = 1                          -- seconds between attaches of what the events could not attach
local painted = {}                       -- gob -> true for every gob wearing our overlay
local painters = {}                      -- peer id -> its painter, built once per peer
local mine                               -- the own gob currently painted
local sweep                              -- the timer, while the link is open

-- The speaker: a body, a cone and two waves, centred a name label's height above the point the label
-- stands on -- and struck through in red for a peer you muted.
local function speaker(g, sx, sy, struck)
  local cy = sy - 26
  g:color(struck and 170 or 140, struck and 170 or 230, struck and 170 or 140)
  g:frect(sx - 8, cy - 3, 4, 6)
  g:poly(sx - 4, cy - 3, sx + 1, cy - 7, sx + 1, cy + 7, sx - 4, cy + 3)
  g:line(sx + 4, cy - 4, sx + 6, cy)
  g:line(sx + 6, cy, sx + 4, cy + 4)
  g:line(sx + 7, cy - 7, sx + 10, cy)
  g:line(sx + 10, cy, sx + 7, cy + 7)
  if struck then
    g:color(230, 70, 70)
    g:line(sx - 10, cy + 9, sx + 11, cy - 9, 2)
  end
  g:color()
end

local function ownPainter(g, gob, sx, sy)
  if link and link:speaking() then speaker(g, sx, sy, false) end
end

local function peerPainter(peer)
  local fn = painters[peer:id()]
  if not fn then
    fn = function(g, gob, sx, sy)
      if peer:muted() then
        speaker(g, sx, sy, true)
      elseif peer:speaking() then
        speaker(g, sx, sy, false)
      end
    end
    painters[peer:id()] = fn
  end
  return fn
end

-- Attach to a gob that is there and bare; a gob whose drawing is still resolving refuses, and the sweep
-- is the retry.
local function paint(gob, fn)
  if not gob or not gob:exists() or gob:overlay():get("voice") then return end
  if pcall(function() gob:overlay():add("voice"):draw(fn) end) then painted[gob] = true end
end

local function unpaint(gob)
  if gob and painted[gob] then
    painted[gob] = nil
    gob:overlay():remove("voice")
  end
end

local function paintAll()
  if not link or link:state() ~= "open" then return end
  local s = link:session()
  local me = s and s:player():gob()
  if me ~= mine then unpaint(mine); mine = me end
  paint(me, ownPainter)
  for _, peer in ipairs(link:peer():list()) do paint(peer:gob(), peerPainter(peer)) end
end

local function clearAll()
  if sweep then sweep:cancel(); sweep = nil end
  for gob in pairs(painted) do gob:overlay():remove("voice") end
  painted, painters, mine = {}, {}, nil
end

-- THE WINDOW. Built by :voice and destroyed by :voice or its own close button, in the layer, its place
-- remembered for the account. What it shows is read from the link on a timer while it stands -- the
-- status line, the two toggles, each peer's glyphs -- and its rows are rebuilt when a peer comes or goes.
local REFRESH = 1                        -- seconds between reads of the link while the window stands
local win, panel, status, muteBox, deafBox, rowsCol, ticker
local rows = {}                          -- peer id -> its row's controls
local rebuildRows                        -- forward: rows are rebuilt from the link's events below

local function peerName(peer)
  local gob = peer:gob()
  local kin = gob and gob:kin()
  return kin and kin:name() or ("#" .. peer:id())
end

local function glyphs(peer)
  return (peer:audible() and "<" or "-") .. " " .. (peer:hears() and ">" or "-")
end

local function statusText()
  if not link then return "no link" end
  local i = link:info()
  local t = i.state
  if i.rtt then t = t .. ", rtt " .. i.rtt .. " ms" end
  if i.state == "open" then t = t .. ", " .. i.streams .. " stream" .. (i.streams == 1 and "" or "s") end
  return t
end

-- What a timer reads back while the window stands: the status, the toggles a hotkey may have moved, and
-- each row's glyphs and mute -- a mute set from the ring reaches the row the same way.
local function refresh()
  if not win or not win:exists() then return end
  status:text(statusText())
  muteBox:value(muted)
  deafBox:value(deafened)
  for _, r in pairs(rows) do
    r.glyph:text(glyphs(r.peer))
    r.mute:value(r.peer:muted())
  end
end

rebuildRows = function()
  if not win or not win:exists() then return end
  if rowsCol then rowsCol:destroy() end
  rows = {}
  rowsCol = hafen.ui():column():gap(2):parent(panel)
  local peers = link and link:state() == "open" and link:peer():list() or {}
  if #peers == 0 then
    hafen.ui():label():parent(rowsCol):text("nobody near")
  end
  for _, peer in ipairs(peers) do
    local row = hafen.ui():row():gap(6):parent(rowsCol)
    local name = hafen.ui():label():parent(row):text(peerName(peer))
    local glyph = hafen.ui():label():parent(row):text(glyphs(peer))
    local mute = hafen.ui():check():parent(row):text("mute"):value(peer:muted())
      :tooltip("Discard this player's voice")
    local vol = hafen.ui():slider():parent(row):size(100):range(0, 400)
      :value(math.floor(peer:volume() * 100 + 0.5)):tooltip("How loud this player is played, 0..400%")
    mute:on("Changed", function(on) peer:muted(on) end)
    vol:on("Changed", function(ev) peer:volume(ev:value() / 100) end)
    rows[peer:id()] = {peer = peer, name = name, glyph = glyph, mute = mute, vol = vol}
  end
  refresh()                              -- the status moved with whatever moved the rows
end

local function closeWindow()
  if ticker then ticker:cancel(); ticker = nil end
  if win and win:exists() then win:destroy() end
  win, panel, status, muteBox, deafBox, rowsCol, rows = nil, nil, nil, nil, nil, nil, {}
end

local function openWindow()
  closeWindow()
  win = hafen.ui():window():title("Voice")
  panel = hafen.ui():column():gap(4):parent(win):position(0, 0)
  status = hafen.ui():label():parent(panel):text(statusText())
  local toggles = hafen.ui():row():gap(8):parent(panel)
  muteBox = hafen.ui():check():parent(toggles):text("muted"):value(muted)
    :tooltip("Nothing of yours goes out")
  deafBox = hafen.ui():check():parent(toggles):text("deafened"):value(deafened)
    :tooltip("Nothing of theirs is played")
  muteBox:on("Changed", function(on)
    muted = on
    if link then link:muted(on) end
  end)
  deafBox:on("Changed", function(on)
    deafened = on
    if link then link:deafened(on) end
  end)
  rebuildRows()
  win:remember("window")                 -- back where it was left; the pack after it keeps the box the rows' own
  win:pack()
  win:on("Close", function()             -- the chrome's close button destroys it: nothing is left to hide
    if ticker then ticker:cancel(); ticker = nil end
    win, panel, status, muteBox, deafBox, rowsCol, rows = nil, nil, nil, nil, nil, nil, {}
  end)
  ticker = hafen.timer():every(REFRESH, refresh)
end

-- ON THE STEP, AND NOT ON THE LINE: a console line runs inside the tree of the character it was typed
-- into, and the window stands in the layer, which no handler may reach while it holds a tree.
hafen.console():on("voice", function()
  hafen.timer():after(0, function()
    if win and win:exists() then closeWindow() else openWindow() end
  end)
end)

-- THE PETAL. A ring opened on another player takes a mute of that player: the peer is minted from the
-- gob whether or not the server relates you yet, so the mute is set before they are near. The pick runs
-- under the ring's tree, so the window is refreshed from the step.
hafen.event():on("FlowerMenuAdded", function(petals, s)
  local gob = s:flowermenu():gob()
  if not link or link:state() ~= "open" or not gob or not gob:player() then return end
  if gob == s:player():gob() then return end
  local peer = link:peer():get(gob)
  s:flowermenu():add(peer:muted() and "Unmute voice" or "Mute voice", function()
    peer:muted(not peer:muted())
    hafen.timer():after(0, refresh)
  end)
end)

-- What the mode means for the two gates, written whenever either the mode or the talk key moves: the key
-- held opens the microphone whatever the mode, so a detection-mode player can push a quiet sentence through.
local function applyMode()
  if not link then return end
  if talking then
    link:vad(false):transmitting(true)
  elseif mode:value() == "push to talk" then
    link:vad(false):transmitting(false)
  elseif mode:value() == "voice detection" then
    link:vad(true):transmitting(true)
  else
    link:vad(false):transmitting(true)
  end
end

local function inWorld()
  return hafen.session():find(function(s) return s:player():gob() ~= nil end) ~= nil
end

local connect

local function schedule()
  if retry then return end
  log("reconnecting in " .. delay .. " s")
  retry = hafen.timer():after(delay, function() retry = nil; connect() end)
  delay = math.min(delay * 2, MAX_DELAY)
end

-- Exactly one of Close and Error ends a link, and the reconnect is decided here rather than beside the
-- close that asked for it: a :connect() to the same server is refused until the ending has run.
local function ended(ev, what)
  if ev:connection() ~= link then return end            -- a link already replaced
  link = nil
  clearAll()
  rebuildRows()
  log(what)
  if not voiceOn:value() then pending = false; return end
  if pending then
    pending = false
    connect()
  elseif inWorld() then
    schedule()
  end
end

connect = function()
  if link or not voiceOn:value() or not inWorld() then return end
  link = hafen.voice():connection(SERVER)
    :spatial(spatial:value())
    :bitrate(bitrate:value())
    :threshold(threshold:value())
    :agc(agc:value())
    :volume(volume:value() / 100)
    :muted(muted)
    :deafened(deafened)
  applyMode()
  link:on("Open", function(v)
    delay = MIN_DELAY
    log("open, session " .. tostring(v:id()))
    paintAll()
    sweep = hafen.timer():every(SWEEP, paintAll)
    rebuildRows()
  end)
  link:on("PeerAdded", function(peer)
    paint(peer:gob(), peerPainter(peer))
    rebuildRows()
  end)
  link:on("PeerRemoved", function(peer)
    unpaint(peer:gob())
    painters[peer:id()] = nil
    rebuildRows()
  end)
  link:on("Close", function(ev) ended(ev, "closed: " .. ev:reason()) end)
  link:on("Error", function(ev) ended(ev, "error: " .. ev:error()) end)
  local ok, err = pcall(link.connect, link)
  if not ok then                                        -- refused before it went anywhere: no ending will come
    link = nil
    log("error: " .. tostring(err))
  end
end

-- THE OPTIONS, each written through as it moves. The two connect-time ones close the link and let its
-- ending build the next; the live ones reach the link at once, or wait in the option for the next connect.
voiceOn:on("Changed", function(v)
  if v then
    if link then pending = true else connect() end
  else
    pending = false
    if retry then retry:cancel(); retry = nil end
    if link then link:close() end
  end
end)
local function reconnect()
  if link then pending = true; link:close() end
end
spatial:on("Changed", reconnect)
bitrate:on("Changed", reconnect)
mode:on("Changed", applyMode)
threshold:on("Changed", function(v) if link then link:threshold(v) end end)
agc:on("Changed", function(v) if link then link:agc(v) end end)
volume:on("Changed", function(v) if link then link:volume(v / 100) end end)

-- THE PAGE, rebuilt on every visit: a control per option, bound to it, and a caption beside each slider
-- that follows the slider's own Changed while the page stands.
local function slider(root, caption, opt, show)
  local label = hafen.ui():label():parent(root):text(caption .. ": " .. show(opt:value()))
  hafen.ui():slider():parent(root):size(200):bind(opt)
    :on("Changed", function(ev) label:text(caption .. ": " .. show(ev:value())) end)
end
opts:panel(function(root)
  root:gap(4)
  hafen.ui():check():parent(root):text("Voice on")
    :tooltip("Hold a link to voice.brodgar.io while a character is in the world"):bind(voiceOn)
  hafen.ui():label():parent(root):text("Mode")
  hafen.ui():dropdown():parent(root):size(160)
    :tooltip("Push to talk: the talk key is the microphone. Voice detection: what is louder than the"
             .. " threshold goes out. Open mic: everything goes out"):bind(mode)
  slider(root, "Threshold", threshold, tostring)
  hafen.ui():check():parent(root):text("Automatic gain")
    :tooltip("Even out your loudness before it goes"):bind(agc)
  hafen.ui():check():parent(root):text("Spatial")
    :tooltip("Pan and fade every voice by where its player stands; reconnects"):bind(spatial)
  slider(root, "Volume", volume, function(v) return v .. "%" end)
  slider(root, "Bitrate", bitrate, tostring)
end)

-- THE KEYS, declared at load so the user's assignment is held from the first frame. talk is a level: the
-- hotkey fires on the way down and a poll reads the key until it comes up.
local keys = hafen.client():options():keybindings()
local talk, poll
keys:on("talk", function()
  if poll then return end
  talking = true
  applyMode()
  poll = hafen.timer():every(POLL, function()
    if talk:down() then return end
    poll:cancel(); poll = nil
    talking = false
    applyMode()
  end)
end)
talk = keys:binding():get("talk")        -- after the declaration: before it, "talk" names no binding of ours
keys:on("mute", function()
  muted = not muted
  if link then link:muted(muted) end
  log(muted and "muted" or "unmuted")
  refresh()
end)
keys:on("deafen", function()
  deafened = not deafened
  if link then link:deafened(deafened) end
  log(deafened and "deafened" or "undeafened")
  refresh()
end)

-- THE MOMENT: the first character in the world. A :reload announces every session in the world again,
-- and an enable finds them by hand; either way one link, because connect() builds none beside a live one.
hafen.event():on("SessionEnteredWorld", function() if not retry then connect() end end)
-- The link follows the screen, so the character it speaks for changes with it: the speaker moves too.
hafen.event():on("SessionSelected", paintAll)
connect()
