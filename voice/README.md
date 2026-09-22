# Voice

Talk to the players near your character. They hear you while they are close enough, and you hear each of
them from the direction they stand in, fading as they walk away.

The addon connects by itself when a character enters the world, so there is nothing to start.

## Talking

How your voice goes out is the **Mode**, in Options ▸ AddOns ▸ Voice:

| Mode | Your voice goes out |
|---|---|
| **push to talk** (the default) | while you hold the `talk` key |
| **voice detection** | whenever you are louder than the threshold |
| **open mic** | always |

Holding the `talk` key opens the microphone in every mode, so a sentence too quiet for voice detection
still goes through.

## Keys

The three keys start unbound — assign them in Options ▸ Game ▸ Keybindings ▸ Voice.

| Key | Suggested | What it does |
|---|---|---|
| `talk` | `V` | held, sends your voice |
| `mute` | `Ctrl+M` | stops your voice going out |
| `deafen` | `Ctrl+D` | stops every voice coming in |

## Who is talking

A speaker is drawn above the name of whoever is talking: over your own character while your voice goes
out, over a nearby player while theirs arrives, and struck through in red over a player you muted.

## The window

`:voice` opens and closes it. At the top, whether the link is up and a **muted** and a **deafened** box;
below, one row per player near you:

| On the row | Means |
|---|---|
| their name, or `#` and a number | the player, named once your character can see them |
| `<` | you hear them |
| `>` | they hear you |
| **mute** | discard their voice |
| the slider | how loud they are played, `0..400%` |

A mute stays with that player while they walk out of range and back, and through a logout. You can also
mute a player from anywhere: right-click them and the ring carries **Mute voice**.

## Options

Options ▸ AddOns ▸ Voice:

| Option | What it does |
|---|---|
| **Voice on** | on by default; off disconnects |
| **Mode** | push to talk, voice detection or open mic |
| **Threshold** | how loud you have to be to count as talking in voice detection; lower is more sensitive |
| **Automatic gain** | evens out your loudness before it goes |
| **Spatial** | pans and fades every voice by where its player stands |
| **Volume** | how loud every voice is played, `0..400%` |
| **Bitrate** | the quality your voice is sent at, `8000..64000` |

## Permissions

- `voice.connect` — opens your microphone and talks to `voice.brodgar.io`. The microphone opens for that
  server and no other, and your position leaves the client only as how far the players near you are from
  you.
