# Voice

Talk to the players near your character. They hear you while they are close enough, and you hear each of
them from the direction they stand in, fading as they walk away.

The addon connects by itself when a character enters the world, so there is nothing to start.

## Usage

1. Assign the keys in **Options ▸ Game ▸ Keybindings ▸ Voice**. They start unbound, like every addon
   hotkey. Suggested: `V` for **talk**, `Ctrl+M` for **mute** and `Ctrl+D` for **deafen**.
2. Hold **talk** to speak. **mute** stops your voice going out; **deafen** stops every voice coming in.
3. A speaker is drawn above the name of whoever is talking: over your own character while your voice goes
   out, over a nearby player while theirs arrives, and struck through in red over a player you muted.

Type `:voice` at the console to open the window, and again to close it. At the top it says whether the
link is up, with a **muted** and a **deafened** box; under that there is a row per player near you, with
their name — or `#` and a number until your character can see them — a `<` while you hear them, a `>`
while they hear you, a **mute** button and a slider for how loud they are played.

You can also mute someone from anywhere: right-click them and the ring carries **Mute voice**. A mute
stays with that player while they walk out of range and back, and through a logout.

## Options

**Options ▸ AddOns ▸ Voice**:

- **Voice on** — on by default. Off disconnects.
- **Mode** — **push to talk** sends while you hold the talk key, **voice detection** sends whenever you
  are louder than the threshold, and **open mic** always sends. Holding the talk key opens the microphone
  in every mode, so a sentence too quiet for voice detection still goes through.
- **Threshold** — how loud you have to be to count as talking in voice detection. Lower is more sensitive.
- **Automatic gain** — evens out your loudness before it goes.
- **Spatial** — pans and fades every voice by where its player stands.
- **Volume** — how loud every voice is played, 0 to 400%.
- **Bitrate** — the quality your voice is sent at.
