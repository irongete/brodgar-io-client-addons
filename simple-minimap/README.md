# Simple Minimap

**This addon takes the client's minimap out of the corner and puts it in a panel of its own.** Not a
minimap of its own — *the* minimap: the same `CornerMap` widget the client built, moved into a panel this
addon owns. So a click still walks you there, the wheel still zooms, and the icons, the markers and the
tooltips are all still the client's. Nothing here draws a map.

The panel is a frame around the map and a row of the corner's buttons above it — personal claims, village
claims, provinces, icon settings — and nothing else: no title, no close button, nothing that could put the
map away. The buttons are the client's own too, moved in with the map, so what they toggle, their tooltips
and their keybindings are untouched.

| You do | It does |
|---|---|
| enable it | the map and its four buttons move into the panel, on every character you have logged in |
| **drag the panel**, anywhere the map or a button is not | moves it where you want it |
| **drag the corner grip**, bottom right | makes the map bigger or smaller |
| **press a button** in the row | what the corner's button did: shows claims, villages or provinces on the world, opens Icon settings |
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

**The buttons are taken, not remade.** Four of the corner's five buttons come along into the panel, the
same way the map does: `button:parent(panel)` in, `button:parent(nil)` back. Nothing here knows what a
button does — the claims switches flip the client's own overlay counters and the icon button opens the
client's own settings window, and none of that is a message to the server. The **Map** button stays in the
corner, put away with it: the big map opens from its key. Each of these buttons is a picture the size of the
whole corner panel, transparent but for its own button, and the client routes a press by the picture's
alpha; the addon places each so its button lands in a slot of the row and lets the rest hang out, where it
draws nothing and takes no press.

The map is **still one character's widget**, so there is one panel per character, each showing that
character's own map. They share the place and the size, because the panel is where *you* want the map, not
where a character does.

## It is a bare panel, and that is the whole design

It was a window first, and a window is the wrong thing for this. A window's decoration keeps a **caption
band** above the content whether there is a caption or not, draws a **caption plate** on it, and carries a
**close button** — and Escape — that would destroy the window with the map still inside. Every one of those
had to be hidden, cancelled or styled away, and a theme could bring any of them back. A bare
`hafen.ui():widget()` has none of them.

So the panel builds the three things a window would have given it, each from the client's own parts:

- **The look is a stock**, not a rule: the client's plain eight-piece box (`gfx/hud/wnd`) as the `border`,
  over its own window field (`gfx/hud/wnd/lg/bg`) as the `bg`. A stock is the bottom of the cascade, so a
  [theme](../themes) naming the panel beats it, property by property:

  ```json
  "[name=simple-minimap/map]": { "bg": { "color": [9, 13, 22, 224] } }
  ```

- **A field under everything is the drag handle**: a bare surface the size of the panel, added before the
  map. Not the panel itself — a handle's press is taken ahead of its own children, so the panel as its own
  handle would swallow the map's clicks and the buttons'. The map takes the clicks meant for it, a button
  takes a press on its picture and passes on one beside it, and whatever reaches the field moves the panel
  after the pointer, with the client's own rule that at least 100 px of it stay on screen.

- **A grip of the addon's sizes it**, a 25 px square in the bottom-right corner drawn with the client's own
  sizer (`gfx/hud/wnd/sizer`) and armed with `panel:resizable(grip)`. It is added after the map, so a press
  in the corner is its and not a walk.

**The grip drives the panel, and the map follows.** The gesture writes the panel's box; the map is kept
that box less the button row and the frame on every frame, so it follows the drag live, and the floor — a
map no smaller than 64 px, and no narrower than the row — is applied once, on release, which is when the
size is saved. Where the panel stands is saved the same way, on the release of a drag.
