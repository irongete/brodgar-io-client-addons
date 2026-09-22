# Gob Cache Map

Every tree and boulder any of your characters walks past is written down. When you need one again, open
the window, type a name and pick a row: the map inside the window goes there.

## Usage

1. Assign a key in **Options ▸ Game ▸ Keybindings ▸ Gob Cache Map ▸ `toggle`** (suggested: `Ctrl+G`).
   Addon hotkeys start unbound, so nothing is claimed until you assign it.
2. Press the key to open the window. Type part of a species or a kind in the field — `fir`, `gneiss`,
   `boulder` — and leave it empty for everything. **Trees** and **Boulders** say which kinds are listed.
3. Pick a row and the map goes there. The list holds the nearest 200 hits, nearest first; `t` is tiles
   away, and `far` means another explored area.

On the map itself: **click a mark** to pick it, **click anywhere else** to look there and let the pick go,
**drag** to pan, and **the wheel** to zoom. **Here** brings it back to the character on screen. The white
dot is that character, the crosshair is where the map is pointed, and the yellow box is the row you
picked.

## Notes

- A hit is drawn as the game's own minimap icon for that thing, so the picture reads without a legend.
  Where the game draws no icon, the mark is a coloured pip instead.
- The ground under it is the client's own map: a place you have never explored is simply not drawn, and
  one you explored a year ago is drawn as it was a year ago.
- There is one cache for the whole client, so every character you play reads and writes the same map.
- A felled tree is forgotten once you stand near where it was and do not see it. Further off nothing is
  forgotten — an object you cannot see from where you are is not gone, only out of range.
- It does not move the client's own map window; the map that goes where you point it is the one in this
  window.
- Typing `:gobcache clear yes` at the console throws the whole cache away.
