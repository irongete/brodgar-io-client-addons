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

## Test one

An addon is loaded from the folder the client's `haven.addondir` names: point the launcher's `addons.dir`
(Options) at this checkout and the client runs what you are editing, reloaded in-game with `:reload`; or
`ant bin` in the client checkout copies every addon here into its `bin/addons/`. There is no beta for an
addon — the hub has no channels, so a published version is what every client installs — so this is where
it is tried.

## Publish one

Once: create a token in [Configuration](https://brodgar.io/addons/settings) and put it in a `.env` file
at the root of this repo (git ignores it):

```
BRODGAR_TOKEN=bio_...
```

Then commit the addon's changes and, from PowerShell:

```powershell
.\publish.ps1 gob-cache-map                 # the next number: 1.0.0 -> 1.0.1
.\publish.ps1 -Version 2.0.0 gob-cache-map  # this number
```

A version is `X.Y.Z`, and every publish takes a new number: Z + 1 of the highest so far — the manifest's, or
the hub's latest when that is higher. [`publish.ps1`](publish.ps1) refuses an addon folder with uncommitted
changes, writes the version into `manifest.json`, zips the folder, uploads it to
[the hub](https://brodgar.io/addons) and commits the manifest as `<id> <version>`, so every published
version is a commit. If the upload fails the manifest is put back and nothing is committed.

## The addons

| Addon | What it does | Permissions it asks for |
|---|---|---|
| `actionbars` | Replaces the client's action bar with as many as the game has slots for: one bar per page of the server's 144, twelve buttons each, flat or upright, drag-and-drop from the action menu and a hotkey per slot | `actionbar.use`, `actionbar.res`, `actionbar.clear` |
| `auto-flowermenu` | Whenever a radial menu opens, picks the first petal on your list that the ring offers — a list of captions you add and order by priority in Options ▸ AddOns | `flowermenu.select` |
| `auto-toggle` | Turns on the toggles you pick, Criminal Acts and Swimming among them, and puts the character on the speed you pick, every time a character logs in; picked in Options ▸ AddOns on a grid of the action menu's own icons, full colour where picked and dark where not, and on a row of the client's own speed pictures | `menugrid.use`, `speed.set` |
| `autodrop` | Names a set of items and throws every one of them on the ground the moment it reaches that character's backpack — and what carries a count of its own, seeds above all, only once that count is 50 | `item.drop` |
| `extended-village-permissions` | Assign up to 255 groups (0-254) beyond the client's native limit of eight, and type a group number into a village's member list to see only that group | `widget.value` |
| `builder-helper` | Remembers what every building site you have opened still needs, and one key floats each material's have/total over the site | — |
| `crop-stage-indicator` | Shows the growth stage number over every crop in view, toggled with a hotkey | — |
| `essentials` | What the client does for a character the moment it enters the world: the toggles, the inventory and the movement speed, each a row in Options ▸ AddOns | `menugrid.use`, `speed.set` |
| `eventstack` | A live log of what the client does: every message out, every update in, every event on the bus, and every widget coming and going — narrowed by session, widget and event, and one click for what a row carried | — |
| `gob-cache-map` | Writes down every tree and boulder you walk past, and finds one again: search a name, pick a row, and the map goes there | — |
| `hitboxes` | Draws the footprint of every game object in view, and of the building you are placing, on the ground — hidden by what stands in front of it, or drawn through everything; one key cycles the modes | — |
| `hud` | Health, stamina and energy as three flat bars of their own, each placed with ALT and a drag and sized and coloured by a slider apiece; switched on, the client's own three meters are hidden | — |
| `immersion` | Labels the nearest game object within a 180-degree cone in front of the character on screen with a floating "this", following it as you move and clearing it when nothing qualifies | `gob.click` |
| `inspector-gadget` | A magnifying glass in the action menu | `menugrid.use`, `gob.click` |
| `item-drop-protection` | With an item on the cursor: left click walks, Ctrl+left click drops | `player.move`, `widget.send` |
| `item-indicators` | Two readings on every item icon: the quality it states, and the durability it has left | — |
| `object-radius-indicator` | A round patch laid on the ground under every object on its list that is in view, following it as it moves | — |
| `paint` | Draw on the ground with the mouse | — |
| `profiler` | Where the frame went — a six-tab window over `hafen.client():profiling()` with the frame graph and phases, render passes and GL counters, per-widget and per-addon cost, the pull-only counters and the overhead accounting | `client.settings` |
| `quick-search` | Press Ctrl+Space, type part of an action's name and run it without opening the action menu | `menugrid.use`, `client.settings`, `console.run` |
| `resourcestack` | Every resource the client holds, as a searchable list — pick one and the panel shows its version, a preview of its image and every layer with what `layer:info()` decodes (image geometry, tooltip and pagina text, audio volume, neg and obst rings, anim frames, props and meta); Fetch asks the client for a name it has not loaded yet and follows the load or its error | — |
| `session-manager` | One row per login the client holds: go to that character, log it out, or cycle to the next with a hotkey | `session.close` |
| `simple-chat` | Replaces the client's chat with a window whose channels are tabs across the top, dragged by its body and resized from the bottom-right corner | `chat.send`, `console.run` |
| `simple-gob-hider` | One key hides the game objects whose resource is on its list and paints a yellow patch over the ground each of them stands on | — |
| `simple-minimap` | Puts the corner minimap in a bare panel of its own, the claim, province and icon buttons in a row above it: no title, no close button, dragged from anywhere on it, sized by a grip in its corner, dressed by any theme that names it | — |
| `stockpile-take` | Type how many items you want out of a stockpile and take them all with one press | `widget.send` |
| `themes` | Loads whole client looks from JSON files in its own `themes/` folder and installs one | — |
| `translations` | Displays the client in the language you pick in Options ▸ AddOns, and helps you write a new one: with the helper on, every string the language does not name yet is collected while you play, translated one by one in the translator window and exported as the JSON file a language ships as | — |
| `trellis-builder` | Pick a block pile, a string pile and a patch of ground, press Start, and the character walks the route itself and fills the patch with trellises — as many per tile as the trellis's own footprint leaves room for | `player.move`, `gob.click`, `world.place`, `menugrid.use`, `widget.send` |
| `voice` | Talk to the players near your character with a push-to-talk key, and hear each of them from the direction they stand in | `voice.connect` |
| `wasd-movement` | Walk with W, A, S and D | `player.move`, `widget.send` |
| `water-meter` | A stamina-shaped bar counting every drop of water you are carrying | — |
| `waypoints` | Queue movement orders and see where your character is headed with an on-map visual indicator | `player.move` |
| `widgetstack` | What a widget is and how to name it — a live stack of the widgets under the cursor, a click-to-inspect window over `hafen.ui()`'s tree reads, a selector inspector that offers only selectors which actually resolve to the widget you are pointing at, and a live treeview of every widget the character has up, to expand, outline and inspect | — |

An addon with a `—` in the last column reads the game and writes only what is client-local; the others
act on your behalf through the key they name, and the client asks you once before they may.
