-- The console command, the ring petal, the hotkeys, and the moment the first link is opened.

local Link = Voice.Link
local Window = Voice.Window
local Overlay = Voice.Overlay

local TALK_POLL_INTERVAL = 0.05    -- seconds between reads of the talk key while it is held

-- A console handler runs inside the tree of the character the line was typed into, and the window stands
-- in the layer, which no handler holding a tree may reach: the toggle runs on the next step instead.
hafen.console():on("voice", function()
  hafen.timer():after(0, Window.toggle)
end)

-- A ring opened on another player takes a mute of that player. The peer is minted from the gob whether or
-- not the server relates you to them yet, so a player can be muted before they are near.
hafen.event():on("FlowerMenuAdded", function(petals, session)
  local gob = session:flowermenu():gob()
  if not Voice.link or Voice.link:state() ~= "open" or not gob or not gob:player() then return end
  if gob == session:player():gob() then return end
  local peer = Voice.link:peer():get(gob)
  session:flowermenu():add(peer:muted() and "Unmute voice" or "Mute voice", function()
    peer:muted(not peer:muted())
    hafen.timer():after(0, Window.refresh)   -- the pick runs under the ring's tree
  end)
end)

-- The three keys start unbound, and are declared at load so the user's assignment holds from the first
-- frame. talk is a level: the hotkey fires on the way down and a poll reads the key until it comes up.
local keybindings = hafen.client():options():keybindings()
local talkBinding, talkPoll
keybindings:on("talk", function()
  if talkPoll then return end
  Link.talking(true)
  talkPoll = hafen.timer():every(TALK_POLL_INTERVAL, function()
    if talkBinding:down() then return end
    talkPoll:cancel()
    talkPoll = nil
    Link.talking(false)
  end)
end)
talkBinding = keybindings:binding():get("talk")   -- before the declaration above, "talk" names no binding

keybindings:on("mute", function()
  Voice.setMuted(not Voice.muted)
  Voice.log(Voice.muted and "muted" or "unmuted")
  Window.refresh()
end)
keybindings:on("deafen", function()
  Voice.setDeafened(not Voice.deafened)
  Voice.log(Voice.deafened and "deafened" or "undeafened")
  Window.refresh()
end)

-- The first character in the world opens the link; connect() builds none beside a live one, so a :reload
-- announcing every session again still leaves one link.
hafen.event():on("SessionEnteredWorld", function()
  if not Link.retrying() then Link.connect() end
end)

-- The link follows the screen, so the character it speaks for changes with it and the speaker moves too.
hafen.event():on("SessionSelected", Overlay.refresh)

Link.connect()
