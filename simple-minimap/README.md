# Simple Minimap

**This addon takes the client's minimap out of the corner and puts it in a window of its own.** Not a
minimap of its own — *the* minimap: the same `CornerMap` widget the client built, moved into a window this
addon owns. So a click still walks you there, the wheel still zooms, and the icons, the markers and the
tooltips are all still the client's. Nothing here draws a map.

| You do | It does |
|---|---|
| enable it | the map moves into a window titled **Minimap**, on every character you have logged in |
| **drag the title** | moves the window where you want it |
| **drag the corner grip**, bottom right | makes the map bigger or smaller |
| press the **X** (or Escape while the window has the focus) | puts it away — the client's own corner returns |
| type `:simpleminimap` | puts it away, or brings it back |
| disable it, or `:reload` | gives the corner back exactly as the client had it |

Where you put it and how big you made it are remembered **for the account**: it is a fact about how you want
the HUD to look, not about who you are playing.

## What it takes, and what it gives back

While it runs, **the bottom-left corner is empty**: the carved plate the client blits round the map, the
map, claim and icon buttons beside it, and the little arrows that fold them away all go, and all come back
when the addon does.

They go as **two panels** rather than as a list of widgets, and that is not a shortcut. The plate and one
arrow hang in the panel the map came out of; the buttons and two more arrows hang in the panel beside it.
Put the buttons away one by one and an arrow is left floating over an empty corner, because that arrow is
their *sibling* and not their child. The panel the map came out of can be put away precisely because the map
is not in it any more.

The map is **still one character's widget**, so there is one window per character, each showing that
character's own map. They share the place and the size, because the window is where *you* want the map, not
where a character does.

## It is a window, and that is the whole design

A window's frame already has every handle a panel of its own would have to build: the **caption drags it**,
the **corner grip sizes it** — the client's own, switched on with `window:resizable(true)`, the one it sizes
its big map from — and the frame is the client's own art, or whatever a [theme](../themes) gives its windows.

So the addon declares no look and names no surface. `window.frame` and `window.title` dress it as they dress
every window, a theme's `sizer` is the grip it shows, and a rule for this window alone is the ordinary one:

```json
"window[title=Minimap]": { "bg": { "color": [9, 13, 22, 224] } }
```

**The grip drives the window, and the map follows.** The grip writes the window's content box; the map is
kept that box less a small margin on every frame, so it follows the drag live, and the floor — a map no
smaller than 64 px — is applied once, on release, which is when the size is saved. The margin is the grip's
room: the grip is a 25 px triangle in the content's bottom-right corner, drawn *under* the content and
offered a press *after* it, so a map that reached the corner would take every press meant for it.

**The X means what `:simpleminimap` means.** A window's close button — and Escape, while it has the focus,
which is the same door on every window — would destroy the window with the map still inside it. Here it is
cancelled, and what it does instead is put the panel away: the client's corner comes back, and stays back
until the next `:simpleminimap`.
