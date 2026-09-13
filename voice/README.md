# Voice

Proximity voice over `voice.brodgar.io`: the players near your character hear you, and you hear them
panned by where they stand.

## How it works

1. **The link opens by itself** when your first character enters the world, and stays up for as long as
   the client runs — it follows whichever character is on screen. When the server ends it or it fails, the
   addon tries again after a pause that doubles from two seconds up to a minute. Each edge is one line in
   the log: `[voice] open, session N`, `[voice] closed: <reason>`, `[voice] error: <text>`,
   `[voice] reconnecting in N s`.
2. **Talk** the way the mode says: *push to talk* sends only while the `talk` key is held; *voice
   detection* sends whatever is louder than the threshold; *open mic* sends everything. The `talk` key
   held opens the microphone in every mode, so a quiet sentence goes through detection too.
3. **`mute`** stops your voice going out, **`deafen`** stops every voice coming in; each key toggles and
   says which in the log.
4. **Who is talking is drawn over heads**: a speaker icon above your own character's name while your
   voice goes out, one above a nearby player's while theirs arrives, and a struck-through one above a
   player you muted, for as long as the mute stands.
5. **`:voice` opens and closes the window**: the link's state, its round trip and how many voices the mix
   holds, a `muted` and a `deafened` box, and a row per player the server relates you to — their kin name
   or `#id`, `<` while you hear them and `>` while they hear you, a `mute` box and a volume slider
   (`0..400%`). Its close button closes it too, and it comes back where you left it.
6. **Right-click another player** and the ring carries `Mute voice`, or `Unmute voice` once they are
   muted. A mute is remembered on the link by that character's object, so it holds while they walk out of
   range and back, and goes with the login.

## Options

Options ▸ AddOns ▸ Voice:

- **Voice on** — on by default. Off closes the link; on opens it again.
- **Mode** — *push to talk* (the default), *voice detection*, *open mic*.
- **Threshold** — `0..2000`, how loud a frame has to be to count as a voice in *voice detection*; lower is
  more sensitive.
- **Automatic gain** — even out your loudness before it goes.
- **Spatial** — pan and fade every voice by where its player stands. Moving it reconnects the link.
- **Volume** — `0..400%`, the gain every voice coming in is played at.
- **Bitrate** — `8000..64000` bits per second. Moving it reconnects the link.

## Keys

The three keys start unbound — assign them in Options ▸ Game ▸ Keybindings ▸ Voice. Suggested:

- **talk** — `V`
- **mute** — `Ctrl+M`
- **deafen** — `Ctrl+D`

## Notes

- The addon asks once for `voice.connect` over `voice.brodgar.io`: the microphone opens for that server and
  no other, and nothing but relative positions leaves the client. What the server is told is on the client
  repository's [`hafen.voice` page](https://github.com/irongete/brodgar-io-client/blob/HEAD/docs/addons/api/voice/README.md).
- One link per server for the whole client: another addon's link to `voice.brodgar.io` is refused while
  this one holds it.
