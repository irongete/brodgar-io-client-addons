# Hitboxes

Draws the footprint of every game object in view on the ground it stands on — trees, walls, animals,
buildings, building sites — and the footprint of the building you are placing, under the cursor.

## Usage

1. Assign a key in **Options ▸ Game ▸ Keybindings ▸ Hitboxes**.
2. Press it to cycle through the three modes:
   - **off** — nothing is drawn.
   - **ground** — the footprints lie on the terrain and are hidden by whatever stands in front of them:
     a box behind a wall stays behind the wall.
   - **over** — the same footprints, drawn through walls, hills and buildings, so a box inside a house
     or over a hill is visible whole. Your windows still cover them.

The mode is remembered, so the client starts in the one you left it in.

## Options

**Options ▸ AddOns ▸ Hitboxes**:

- **Footprints** — the mode, the same setting the key cycles.
- **Fill colour** — the colour laid over the ground an object stands on.
- **Fill opacity** — per cent. `0` leaves only the border, a footprint drawn as an outline.
- **Border colour** — the line round each footprint, always solid.
- **Border thickness** — in hundredths of a world unit; a tile is 11 units, so `35` is a thin line. `0` is
  the thinnest line the screen can draw. To hide the border, give it the fill's colour.

Every setting is remembered.

## Notes

- An object whose resource carries no shape — most decorations and flooring — gets no footprint.
- A footprint is what the object's resource declares, not proof that it blocks movement: a felled log
  shows a box and can be walked through.
- In **over** mode, overlapping footprints stack in whatever order the client draws them.
