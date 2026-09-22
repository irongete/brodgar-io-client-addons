-- Voice -- the players near your character hear you, and you hear them from where they stand.
--
-- The manifest runs the files in order into one environment; each adds its module under `Voice`:
--   options.lua   the options, the Options page, and the state the other files share (this file)
--   overlay.lua   the speaker drawn over the head of whoever is talking
--   window.lua    the :voice window
--   link.lua      the link to the voice server: building it, its settings, reconnecting
--   main.lua      the console command, the ring petal, the hotkeys and the session events

Voice = {}

-- The live link, nil from the moment its Close or Error has run until the next one is built (link.lua).
Voice.link = nil

-- The two toggles the window and the hotkeys share. Held here rather than read off the link, because a
-- reconnect copies them onto the new one.
Voice.muted = false
Voice.deafened = false

function Voice.log(message)
  hafen.log():write("[voice] " .. message)
end

function Voice.setMuted(flag)
  Voice.muted = flag
  if Voice.link then Voice.link:muted(flag) end
end

function Voice.setDeafened(flag)
  Voice.deafened = flag
  if Voice.link then Voice.link:deafened(flag) end
end

local addonOptions = hafen.client():options():addon()

-- `volume` is a percentage of the link's own 0..4 gain; link.lua divides it by 100.
local Options = {
  enabled = addonOptions:boolean("on"):default(true):add(),
  mode = addonOptions:choice("mode"):choices{"push to talk", "voice detection", "open mic"}
    :default("push to talk"):add(),
  threshold = addonOptions:number("threshold"):range(0, 2000):default(350):add(),
  automaticGain = addonOptions:boolean("agc"):default(true):add(),
  spatial = addonOptions:boolean("spatial"):default(true):add(),
  volume = addonOptions:number("volume"):range(0, 400):default(100):add(),
  bitrate = addonOptions:number("bitrate"):range(8000, 64000):default(24000):add(),
}
Voice.Options = Options

-- A slider and a caption that follows it while the page stands. The page is built again on every visit.
local function addSlider(root, caption, option, format)
  local label = hafen.ui():label():parent(root):text(caption .. ": " .. format(option:value()))
  hafen.ui():slider():parent(root):size(200):bind(option)
    :on("Changed", function(event) label:text(caption .. ": " .. format(event:value())) end)
end

addonOptions:panel(function(root)
  root:gap(4)
  hafen.ui():check():parent(root):text("Voice on")
    :tooltip("Hold a link to voice.brodgar.io while a character is in the world"):bind(Options.enabled)
  hafen.ui():label():parent(root):text("Mode")
  hafen.ui():dropdown():parent(root):size(160)
    :tooltip("Push to talk: the talk key is the microphone. Voice detection: what is louder than the"
             .. " threshold goes out. Open mic: everything goes out"):bind(Options.mode)
  addSlider(root, "Threshold", Options.threshold, tostring)
  hafen.ui():check():parent(root):text("Automatic gain")
    :tooltip("Even out your loudness before it goes"):bind(Options.automaticGain)
  hafen.ui():check():parent(root):text("Spatial")
    :tooltip("Pan and fade every voice by where its player stands; reconnects"):bind(Options.spatial)
  addSlider(root, "Volume", Options.volume, function(value) return value .. "%" end)
  addSlider(root, "Bitrate", Options.bitrate, tostring)
end)
