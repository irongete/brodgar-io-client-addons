# Hider

Takes the kinds of object you tick out of view — trees, bushes, boulders, stockpiles, walls and fences —
and lays a patch on the ground each of them stands on, so you keep sight of the ground and still know what
is there.

## Usage

1. Assign a key in **Options ▸ Game ▸ Keybindings ▸ Hider** (suggested: `Ctrl+H`).
2. Tick what you want out of the way in **Options ▸ AddOns ▸ Hider**. Trees and bushes start ticked.
3. Press the key to hide them, and press it again to bring them back.

While it is on, what comes into view is hidden as it arrives, and a tick you change is applied straight
away. Turning it off brings all of it back, and nothing is remembered: after a logout, or a client
restart, everything is visible again.

## Options

**Options ▸ AddOns ▸ Hider**:

- **What the key hides** — a checkbox each for trees, logs and trunks, stumps, bushes, boulders,
  stockpiles, and the walls and fences: palisade, brick, dry stone and pole, each with its corner posts on
  a line of its own. Hide the walls and keep the corners to see the run of a palisade through it.
- **Fill colour** and **Fill opacity** — the colour laid over the ground a hidden object stood on. `0`
  opacity leaves only the border, so the patch is an outline.
- **Border colour** and **Border thickness** — the line round the patch, always solid. Thickness is in
  hundredths of a world unit, and a tile is 11 units, so `60` is a thin line. To hide the border, give it
  the fill's colour.

Every setting is remembered.

## Notes

- Only the model is hidden. A hidden tree still blocks your way, and its name label and health bar still
  show over the empty ground.
- A click where a hidden object stands goes to the ground under it, so turn Hider off to chop, pick or
  open something it hides.
- The patch lies on the ground itself: it follows a slope, and whatever stands in front of it hides it. It
  goes away with the object, so a felled tree takes its own patch down.
- With more than one character logged in, an object hidden for one is hidden for every one of them that
  can see it.
