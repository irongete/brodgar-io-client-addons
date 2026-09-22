-- The speaker drawn over a head: one overlay named "voice" per gob that has a voice -- the character the
-- link speaks for, and every peer the link relates it to.

local Overlay = {}
Voice.Overlay = Overlay

local SWEEP_INTERVAL = 1      -- seconds between tries at the gobs an event could not attach to

local painted = {}            -- gob -> true for every gob wearing the overlay
local painters = {}           -- peer id -> the painter built for that peer
local paintedOwnGob           -- the character's own gob, while it wears the overlay
local sweepTimer

-- A speaker body, its cone and two waves, centred a name label's height above the point the label stands
-- on, and struck through in red when it stands for a peer you muted.
local function drawSpeaker(graphics, screenX, screenY, struck)
  local centerY = screenY - 26
  graphics:color(struck and 170 or 140, struck and 170 or 230, struck and 170 or 140)
  graphics:frect(screenX - 8, centerY - 3, 4, 6)
  graphics:poly(screenX - 4, centerY - 3, screenX + 1, centerY - 7,
                screenX + 1, centerY + 7, screenX - 4, centerY + 3)
  graphics:line(screenX + 4, centerY - 4, screenX + 6, centerY)
  graphics:line(screenX + 6, centerY, screenX + 4, centerY + 4)
  graphics:line(screenX + 7, centerY - 7, screenX + 10, centerY)
  graphics:line(screenX + 10, centerY, screenX + 7, centerY + 7)
  if struck then
    graphics:color(230, 70, 70)
    graphics:line(screenX - 10, centerY + 9, screenX + 11, centerY - 9, 2)
  end
  graphics:color()
end

-- The painters read the link on the frame they draw, so nothing here keeps a copy of who is talking.
local function ownPainter(graphics, gob, screenX, screenY)
  if Voice.link and Voice.link:speaking() then drawSpeaker(graphics, screenX, screenY, false) end
end

-- One painter per peer, kept until PeerRemoved so every reattach uses the same function.
local function peerPainter(peer)
  local painter = painters[peer:id()]
  if not painter then
    painter = function(graphics, gob, screenX, screenY)
      if peer:muted() then
        drawSpeaker(graphics, screenX, screenY, true)
      elseif peer:speaking() then
        drawSpeaker(graphics, screenX, screenY, false)
      end
    end
    painters[peer:id()] = painter
  end
  return painter
end

-- Attaches to a gob that is there and bare. A gob whose drawing is still resolving refuses the overlay;
-- the sweep armed by refresh() is the retry.
local function attach(gob, painter)
  if not gob or not gob:exists() or gob:overlay():get("voice") then return end
  if pcall(function() gob:overlay():add("voice"):draw(painter) end) then painted[gob] = true end
end

local function detach(gob)
  if gob and painted[gob] then
    painted[gob] = nil
    gob:overlay():remove("voice")
  end
end

function Overlay.attachPeer(peer)
  attach(peer:gob(), peerPainter(peer))
end

function Overlay.removePeer(peer)
  detach(peer:gob())
  painters[peer:id()] = nil
end

-- Attaches every gob that has a voice and can take the overlay, and keeps a sweep running while the link
-- is open for the ones that could not: a peer's gob may not exist yet when PeerAdded fires. The character
-- the link speaks for changes with the session on screen, so the own gob is checked on every pass.
function Overlay.refresh()
  if not Voice.link or Voice.link:state() ~= "open" then return end
  local session = Voice.link:session()
  local ownGob = session and session:player():gob()
  if ownGob ~= paintedOwnGob then
    detach(paintedOwnGob)
    paintedOwnGob = ownGob
  end
  attach(ownGob, ownPainter)
  for _, peer in ipairs(Voice.link:peer():list()) do
    attach(peer:gob(), peerPainter(peer))
  end
  if not sweepTimer then sweepTimer = hafen.timer():every(SWEEP_INTERVAL, Overlay.refresh) end
end

-- Takes every overlay off and stops the sweep: the link has ended.
function Overlay.clear()
  if sweepTimer then
    sweepTimer:cancel()
    sweepTimer = nil
  end
  for gob in pairs(painted) do gob:overlay():remove("voice") end
  painted, painters, paintedOwnGob = {}, {}, nil
end
