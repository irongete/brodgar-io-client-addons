# Gob Cache Map

Every tree and boulder any of your characters walks past is written down. When you need one, open the
window, type a name, and pick a row: the map inside the window goes there.

```text
:gobcache
```

Suggested key: `Ctrl+G` — assign it in Options ▸ Game ▸ Keybindings ▸ Gob Cache Map ▸ `toggle`.
An addon hotkey starts unbound, so nothing is claimed until you assign it.

## The window

| | |
|---|---|
| the text field | part of a species or a kind — `fir`, `gneiss`, `boulder`. Empty means everything |
| **Trees**, **Boulders** | which kinds count in the list |
| the list | the nearest 200 hits, nearest first; `t` is tiles, `far` is another explored area |
| **Here** | look at the character on screen |

On the map itself: **click a mark** to pick it, **click anywhere else** to look there and let the pick go,
**drag** to pan — the ground follows the pointer for as long as the button is held, past the edge of the
panel included — and **the wheel** zooms between 1, 2 and 4 tiles to the pixel. The white dot is the
character on screen, the crosshair is where the panel is pointed, and the yellow box is the row you picked.

A hit is drawn as **the game's own minimap icon** for that thing — the same little fir the corner map draws
— so the picture reads without a legend. Where the game draws no icon for something, the mark is a pip in
its kind's colour instead. That is not a guess about which icon belongs to what: the live object is asked
(`gob:icon()`), and the answer is looked up in the client's own icon registry.

The ground under all of it is the client's own minimap art, read out of the map database at its own
colours — so a place you have never explored is simply not drawn, and one you explored a year ago is drawn
as it was a year ago.

## What it writes down, and what it never writes twice

A tree does not move, so a tree **is** its place: the server's grid id plus the offset inside that grid,
which is what `Position:info()` hands back and the one anchor a segment merge never rewrites. The cache is
keyed on exactly that — one row of the `objects` table per `(grid, x, y)`, holding the kind — so the same oak seen on Monday, on
Tuesday, and out of a second character's eyes is one row, and finding that out costs no search at all.

A **different** resource at a place already held overwrites it, which is what a mined-out boulder looks
like from here.

Objects are read by a sweep every three seconds rather than from `GobAdded`, on purpose: subscribing to
that event makes the client hold *every* arriving object out of the scene until the handler has run, and a
cache has no use for immediacy worth that.

## Forgetting a felled tree

Standing within about five tiles of a place it holds and not seeing what it wrote there, three sweeps
running, the addon drops the row. Further off nothing is ever forgotten — an object you cannot see from
where you are is not gone, it is just not streamed in.

## Where the data lives

`savedata/gob-cache-map/gob-cache-map.sqlite`, the addon's own file, as two tables it declares:

| Table | One row per | Key |
|---|---|---|
| `kinds` | resource name seen — `gfx/terobjs/trees/fir` — with the minimap icon it draws, once known | `id` |
| `objects` | thing written down: its grid, its offset in the grid, and the kind standing there | `(grid, x, y)` |

A row is in the file the moment it is written and nothing is ever written whole, so a cache of a few
hundred thousand objects costs a frame what one of a hundred does: the sweep compares what it sees with
the cells of the grids around the character, read once and kept while the character is near, and the list
reads the nearest grids out of the file one at a time until it is full. The window's own settings — the
search, the checkboxes, where the panel is pointed — are a var, which is the shape for a handful of values.

There is one file for the whole client, so every character you play in that world reads and writes the
same cache, which is what a map of the world wants.

## The console

| | |
|---|---|
| `:gobcache` | open and close the window |
| `:gobcache stats` | how much is held, over how many grids, and how many distinct resources |
| `:gobcache scan` | sweep now instead of waiting for the beat |
| `:gobcache clear yes` | throw the whole cache away |

## Widening it

`KINDS`, at the top of `main.lua`, is the whole of what the addon considers. A kind is a substring of the
resource name — that is the only question the client can be asked about a game object — and adding a row
there is enough: the cache, the filter, the list and the marks all read that one table.

```lua
{ key = "bush", label = "Bushes", match = "terobjs/bushes/", color = { 120, 180, 90 } },
```

The list shows the species drawn from the resource name, so anything unexpected the match sweeps in is
visible on its own row rather than hidden in a total.

## What it does not do

It does not move the client's **own** map window. Nothing in the addon API aims that window at a place, so
the map that goes where you point it is the one in this window.

It needs no permissions — it reads the world and the map database, and writes only its own saved file.
