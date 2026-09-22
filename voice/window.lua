-- The :voice window: the link's state, the mute and the deafen, and a row per player near you. It stands
-- in the layer, its place remembered for the account. What it shows is read from the link on a timer
-- while it stands, and its rows are built again whenever a peer comes or goes.

local Window = {}
Voice.Window = Window

local REFRESH_INTERVAL = 1    -- seconds between reads of the link while the window stands

local window, panel, statusLabel, muteBox, deafenBox, rowsColumn, refreshTimer
local rows = {}               -- peer id -> that row's controls

local function peerName(peer)
  local gob = peer:gob()
  local kin = gob and gob:kin()
  return kin and kin:name() or ("#" .. peer:id())
end

-- "<" while you hear them, ">" while they hear you.
local function glyphs(peer)
  return (peer:audible() and "<" or "-") .. " " .. (peer:hears() and ">" or "-")
end

local function statusText()
  if not Voice.link then return "no link" end
  local info = Voice.link:info()
  local text = info.state
  if info.rtt then text = text .. ", rtt " .. info.rtt .. " ms" end
  if info.state == "open" then
    text = text .. ", " .. info.streams .. " stream" .. (info.streams == 1 and "" or "s")
  end
  return text
end

-- Reads back what the link, a hotkey or a ring petal may have moved since the last pass.
function Window.refresh()
  if not window or not window:exists() then return end
  statusLabel:text(statusText())
  muteBox:value(Voice.muted)
  deafenBox:value(Voice.deafened)
  for _, row in pairs(rows) do
    row.glyph:text(glyphs(row.peer))
    row.mute:value(row.peer:muted())
  end
end

function Window.rebuildRows()
  if not window or not window:exists() then return end
  if rowsColumn then rowsColumn:destroy() end
  rows = {}
  rowsColumn = hafen.ui():column():gap(2):parent(panel)
  local peers = Voice.link and Voice.link:state() == "open" and Voice.link:peer():list() or {}
  if #peers == 0 then
    hafen.ui():label():parent(rowsColumn):text("nobody near")
  end
  for _, peer in ipairs(peers) do
    local row = hafen.ui():row():gap(6):parent(rowsColumn)
    local name = hafen.ui():label():parent(row):text(peerName(peer))
    local glyph = hafen.ui():label():parent(row):text(glyphs(peer))
    local mute = hafen.ui():check():parent(row):text("mute"):value(peer:muted())
      :tooltip("Discard this player's voice")
    local volume = hafen.ui():slider():parent(row):size(100):range(0, 400)
      :value(math.floor(peer:volume() * 100 + 0.5)):tooltip("How loud this player is played, 0..400%")
    mute:on("Changed", function(checked) peer:muted(checked) end)
    volume:on("Changed", function(event) peer:volume(event:value() / 100) end)
    rows[peer:id()] = {peer = peer, name = name, glyph = glyph, mute = mute, volume = volume}
  end
  Window.refresh()              -- the status moved with whatever moved the rows
end

-- Drops the handles of a window that is already gone.
local function forget()
  if refreshTimer then
    refreshTimer:cancel()
    refreshTimer = nil
  end
  window, panel, statusLabel, muteBox, deafenBox, rowsColumn, rows = nil, nil, nil, nil, nil, nil, {}
end

local function close()
  if window and window:exists() then window:destroy() end
  forget()
end

local function open()
  close()
  window = hafen.ui():window():title("Voice")
  panel = hafen.ui():column():gap(4):parent(window):position(0, 0)
  statusLabel = hafen.ui():label():parent(panel):text(statusText())
  local toggles = hafen.ui():row():gap(8):parent(panel)
  muteBox = hafen.ui():check():parent(toggles):text("muted"):value(Voice.muted)
    :tooltip("Nothing of yours goes out")
  deafenBox = hafen.ui():check():parent(toggles):text("deafened"):value(Voice.deafened)
    :tooltip("Nothing of theirs is played")
  muteBox:on("Changed", function(checked) Voice.setMuted(checked) end)
  deafenBox:on("Changed", function(checked) Voice.setDeafened(checked) end)
  Window.rebuildRows()
  window:remember("window")     -- back where it was left; the pack after it keeps the box the rows ask for
  window:pack()
  window:on("Close", forget)    -- the chrome's close button destroys it, so only the handles are dropped
  refreshTimer = hafen.timer():every(REFRESH_INTERVAL, Window.refresh)
end

function Window.toggle()
  if window and window:exists() then close() else open() end
end
