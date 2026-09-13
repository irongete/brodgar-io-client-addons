# Brodgar.io client addons

The addons written for the [Brodgar.io client](https://github.com/irongete/brodgar-io-client) by its
maintainer, every one of them in Lua against the client's own `hafen.*` API. Some ship with a client
release and the rest are personal; each folder here is one addon, and the folder name is its id.

## Install one

Copy the addon's folder into the `addons/` folder beside the client (`hafen.jar`) and start the client:
it appears under **Options ▸ AddOns**. An addon that declares a permission is disabled the first time the
client sees it, and asks you to approve what it may do before it runs. How the client loads an addon, what
it may touch and the console commands that drive it are on
[the runtime page](https://github.com/irongete/brodgar-io-client/blob/HEAD/docs/addons/runtime.md).

## Write your own

The API is documented in the client repository, under
[`docs/addons/`](https://github.com/irongete/brodgar-io-client/blob/HEAD/docs/addons/README.md) —
[getting started](https://github.com/irongete/brodgar-io-client/blob/HEAD/docs/addons/getting-started.md)
takes an empty folder to a working addon. Nothing here is a library to build on: a page of the reference
carries its own example.

## The addons

| Addon | What it does | Permissions it asks for |
|---|---|---|
| `actionbars` | Replaces the client's action bar with as many as the game has slots for: one bar per page of the server's 144, twelve buttons each, flat or upright, drag-and-drop from the action menu and a hotkey per slot | `actionbar.use`, `actionbar.res`, `actionbar.clear` |
| `auto-flowermenu` | Whenever a radial menu opens, picks the first petal on your list that the ring offers — a list of captions you add and order by priority in Options ▸ AddOns | `flowermenu.select` |
| `autodrop` | Names a set of items and throws every one of them on the ground the moment it reaches that character's backpack — and what carries a count of its own, seeds above all, only once that count is 50 | `item.drop` |
| `better-village-controls` | A polity's groups run 0 to 254 while the client draws eight colours, so every colour row that spends the whole of that space grows a picker beside it carrying every group the server takes | `widget.value` |
| `builder-helper` | Remembers what every building site you have opened still needs, and one key floats each material's have/total over the site | — |
| `clickpath` | Alt-click queues waypoints, each with a flag, and draws every logged-in character's path over the map, under the client's windows | `player.move` |
| `essentials` | What the client does for a character the moment it enters the world: the toggles, the inventory and the movement speed, each a row in Options ▸ AddOns | `menugrid.use`, `speed.set` |
| `eventstack` | A live log of what the client does: every message out, every update in, every event on the bus, and every widget coming and going — narrowed by session, widget and event, and one click for what a row carried | — |
| `farming-helper` | One key puts the growth stage over every planted crop in sight, read from the state bytes the server sent with it | — |
| `gob-cache-map` | Writes down every tree and boulder you walk past, and finds one again: search a name, pick a row, and the map goes there over a heatmap of the rest | — |
| `hitboxes` | Three modes for the footprint of every game object in view — and of the building you are placing: off, a blue patch laid on the terrain and hidden by whatever stands in front of it, and the same patch told the world may not hide it | — |
| `immersion` | Labels the nearest game object within a 180-degree cone in front of the character on screen with a floating "this", following it as you move and clearing it when nothing qualifies | `gob.click` |
| `inspector-gadget` | A magnifying glass in the action menu | `menugrid.use`, `gob.click` |
| `item-drop-protection` | With an item on the cursor: left click walks, Ctrl+left click drops | `player.move`, `widget.send` |
| `item-indicators` | Two readings on every item icon: the quality it states, and the durability it has left | — |
| `paint` | Draw on the ground with the mouse | — |
| `profiler` | Where the frame went — a six-tab window over `hafen.client():profiling()` with the frame graph and phases, render passes and GL counters, per-widget and per-addon cost, the pull-only counters and the overhead accounting | `client.settings` |
| `session-manager` | One row per login the client holds: go to that character, log it out, or cycle to the next with a hotkey | `session.close` |
| `simple-animal-radius` | A round patch laid on the ground under every aggressive animal in view, following it as it moves | — |
| `simple-chat` | Replaces the client's chat with a window whose channels are tabs across the top, dragged by its body and resized from the bottom-right corner | `chat.send`, `console.run` |
| `simple-gob-hider` | One key hides the game objects whose resource is on its list and paints a yellow patch over the ground each of them stands on | — |
| `simple-minimap` | Puts the corner minimap in the action bars' box: the client's carved plate off, the eight-piece window frame round the map instead | — |
| `stockpile-controls` | Every window titled "Stockpile" grows a little taller and carries a row of its own below the pile: an amount, and a Take button that draws that many items out of the pile and into your backpack | `widget.send` |
| `themes` | Loads whole client looks from JSON files in its own `themes/` folder and installs one | — |
| `translator-helper` | Displays the client in Spanish, Russian or Chinese and collects every string the chosen language does not name yet, so you translate them one by one in a window and see each one on screen the moment it is saved | — |
| `trellis-builder` | Pick a block pile, a string pile and a patch of ground, press Start, and the character walks the route itself and fills the patch with trellises — as many per tile as the trellis's own footprint leaves room for | `player.move`, `gob.click`, `world.place`, `menugrid.use`, `widget.send` |
| `voice` | Proximity voice over `voice.brodgar.io`: one link held for the client's life, a page of settings, push-to-talk, voice detection or an open microphone, a speaker drawn over whoever is talking, a window with a mute and a volume per player, and a mute petal on a player's ring | `voice.connect` |
| `wasd-movement` | Walk with W, A, S and D | `player.move`, `widget.send` |
| `water-meter` | A stamina-shaped bar counting every drop of water you are carrying | — |
| `widgetstack` | What a widget is and how to name it — a live stack of the widgets under the cursor, a click-to-inspect window over `hafen.ui()`'s tree reads, and a selector inspector that offers only selectors which actually resolve to the widget you are pointing at | — |

An addon with a `—` in the last column reads the game and writes only what is client-local; the others
act on your behalf through the key they name, and the client asks you once before they may.
