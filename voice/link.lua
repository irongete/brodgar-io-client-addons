-- The link to the voice server: one for the client's life, opened while a character is in the world,
-- built again after a pause that doubles whenever the server ends it or it fails, and closed by the
-- "Voice on" option.

local Overlay = Voice.Overlay
local Window = Voice.Window
local Options = Voice.Options

local Link = {}
Voice.Link = Link

local SERVER = "wss://voice.brodgar.io"
local MIN_DELAY, MAX_DELAY = 2, 60    -- seconds between a lost link and the next try, doubling

local retryTimer                      -- armed while a try is waiting
local retryDelay = MIN_DELAY
local rebuildWhenEnded                -- the link now closing is to be replaced the moment it has ended
local talking = false                 -- the talk key is held

-- The two gates the mode asks for. The talk key held opens the microphone whatever the mode, so a quiet
-- sentence goes out under voice detection too.
function Link.applyMode()
  local link = Voice.link
  if not link then return end
  if talking then
    link:vad(false):transmitting(true)
  elseif Options.mode:value() == "push to talk" then
    link:vad(false):transmitting(false)
  elseif Options.mode:value() == "voice detection" then
    link:vad(true):transmitting(true)
  else
    link:vad(false):transmitting(true)
  end
end

function Link.talking(flag)
  talking = flag
  Link.applyMode()
end

function Link.retrying()
  return retryTimer ~= nil
end

local function inWorld()
  return hafen.session():find(function(session) return session:player():gob() ~= nil end) ~= nil
end

local function schedule()
  if retryTimer then return end
  Voice.log("reconnecting in " .. retryDelay .. " s")
  retryTimer = hafen.timer():after(retryDelay, function()
    retryTimer = nil
    Link.connect()
  end)
  retryDelay = math.min(retryDelay * 2, MAX_DELAY)
end

-- Exactly one of Close and Error ends a link. The next one is built from here and not beside the close
-- that asked for it, because a :connect() to the same server is refused until the ending has run.
local function ended(event, what)
  if event:connection() ~= Voice.link then return end     -- a link already replaced
  Voice.link = nil
  Overlay.clear()
  Window.rebuildRows()
  Voice.log(what)
  if not Options.enabled:value() then
    rebuildWhenEnded = false
    return
  end
  if rebuildWhenEnded then
    rebuildWhenEnded = false
    Link.connect()
  elseif inWorld() then
    schedule()
  end
end

function Link.connect()
  if Voice.link or not Options.enabled:value() or not inWorld() then return end
  local link = hafen.voice():connection(SERVER)
    :spatial(Options.spatial:value())
    :bitrate(Options.bitrate:value())
    :threshold(Options.threshold:value())
    :agc(Options.automaticGain:value())
    :volume(Options.volume:value() / 100)
    :muted(Voice.muted)
    :deafened(Voice.deafened)
  Voice.link = link
  Link.applyMode()
  link:on("Open", function(opened)
    retryDelay = MIN_DELAY
    Voice.log("open, session " .. tostring(opened:id()))
    Overlay.refresh()
    Window.rebuildRows()
  end)
  link:on("PeerAdded", function(peer)
    Overlay.attachPeer(peer)
    Window.rebuildRows()
  end)
  link:on("PeerRemoved", function(peer)
    Overlay.removePeer(peer)
    Window.rebuildRows()
  end)
  link:on("Close", function(event) ended(event, "closed: " .. event:reason()) end)
  link:on("Error", function(event) ended(event, "error: " .. event:error()) end)
  local connected, failure = pcall(link.connect, link)
  if not connected then                       -- refused before it went anywhere: no ending will come
    Voice.link = nil
    Voice.log("error: " .. tostring(failure))
  end
end

-- Every option is written through as it moves. Spatial and bitrate are legal only before :connect(), so
-- they close the link and let its ending build the next; the rest reach the link at once, or wait in the
-- option until the next one is built.
local function rebuild()
  if Voice.link then
    rebuildWhenEnded = true
    Voice.link:close()
  end
end

Options.enabled:on("Changed", function(value)
  if value then
    if Voice.link then rebuildWhenEnded = true else Link.connect() end
  else
    rebuildWhenEnded = false
    if retryTimer then
      retryTimer:cancel()
      retryTimer = nil
    end
    if Voice.link then Voice.link:close() end
  end
end)
Options.spatial:on("Changed", rebuild)
Options.bitrate:on("Changed", rebuild)
Options.mode:on("Changed", Link.applyMode)
Options.threshold:on("Changed", function(value) if Voice.link then Voice.link:threshold(value) end end)
Options.automaticGain:on("Changed", function(value) if Voice.link then Voice.link:agc(value) end end)
Options.volume:on("Changed", function(value) if Voice.link then Voice.link:volume(value / 100) end end)
