# Simple Minimap

Takes the client's minimap out of the bottom-left corner and puts it in a bare panel of its own, with the
claim, village, province and icon buttons in a row above it. No title, no close button: you drag it from
anywhere on it and size it from the grip in its corner.

It is the client's own minimap, moved — not a new one. A click still walks you there, the wheel still
zooms, and the icons, the markers and the tooltips are all still the client's.

## Usage

1. Enable the addon. The map and its four buttons move into the panel, in the top-right corner of the
   screen, on every character you have logged in.
2. **Drag the panel** — anywhere the map or a button is not — to move it.
3. **Drag the grip** in the bottom-right corner to make the map bigger or smaller.
4. Press a button in the row for what the corner's button did: show personal claims, village claims or
   provinces on the world, or open Icon settings.

Where you put it and how big you made it are remembered for the account, so every character you play sees
the panel in the same place. The place is kept relative to the screen, so it stays put when you resize the
game window or change the interface scale.

## Notes

- While it runs, the bottom-left corner is empty: the plate around the map, its buttons and the little
  arrows that folded them away all go, and all come back when you disable the addon or press
  **Reload UI**.
- The **Map** button stays in the corner and goes away with it. The big map opens from its key.
- There is one panel per character, each showing that character's own map, and they share the place and
  the size: switching to another character puts its panel where you last left one.
- The **Themes** addon can dress the panel, so it matches the rest of your HUD.

## For bundles

An addon that lists `simple-minimap>=1.1.0` in its `dependencies` can start the panel somewhere else, from
its own file:

```lua
hafen.client():addons():get("simple-minimap"):api().preset{
  place = {at = "topright", offset = {-8, 8}},   -- the corner it starts in, as a sheet anchor
  mapSize = {width = 300, height = 300},        -- the size the map starts at
}
```

The numbers are screen pixels, so the panel starts the same size whatever the player's interface scale. Both
only say where the panel starts: once the player moves or sizes it, their place and size win.
