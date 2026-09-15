# GEMINI.md — Brodgar.io Client Addons Development Guidelines

This repository contains addons for the Brodgar.io client (`hafen` engine). All code generated or modified in this repository must strictly adhere to the following rules, adapted from the official client documentation (`C:\Users\irongete\Desktop\github\brodgar-io-client\docs\addons`).

---

## 1. Variable Naming Standards (MANDATORY)

**Strictly descriptive variable names. Single-letter and vague abbreviations are STRICTLY FORBIDDEN.**

Every variable, parameter, and function argument must clearly express its purpose using full, descriptive words.

### Forbidden vs. Mandatory Equivalents:
- ❌ `s` ➔ ✅ `session` (or `current_session`, `active_session`)
- ❌ `w` ➔ ✅ `world`, `widget`, or `window` (never ambiguous `w`)
- ❌ `p` ➔ ✅ `position`, `player`, or `parent_widget`
- ❌ `g` ➔ ✅ `graphics`, `game_object`, or `grid`
- ❌ `ev` ➔ ✅ `event`, `draw_event`, `close_event`, or `input_event`
- ❌ `it`, `c` ➔ ✅ `item`, `container`, or `collection`
- ❌ `b`, `k` ➔ ✅ `binding`, `keybindings`, or `button`
- ❌ `cb`, `fn` ➔ ✅ `callback`, `predicate_function`, or `action_handler`
- ❌ `a`, `res` ➔ ✅ `asset`, `resource_name`, or `result`
- ❌ `o`, `e`, `n` ➔ ✅ `origin_screen`, `east_screen`, `south_screen`
- ❌ `tbl`, `arr` ➔ ✅ Domain-specific names: `active_buttons`, `player_list`, `tracked_gobs`

### In Function Signatures & Callbacks:
```lua
-- FORBIDDEN:
local function screenUp(s, from)
  local w = s:world()
  local o = w:worldToScreen(from)
  local e = w:worldToScreen(from:offset(PROBE, 0))
  local n = w:worldToScreen(from:offset(0, PROBE))
end

-- MANDATORY:
local function calculate_screen_up(session, origin_position)
  local world = session:world()
  local screen_origin = world:worldToScreen(origin_position)
  local screen_east = world:worldToScreen(origin_position:offset(PROBE_DISTANCE, 0))
  local screen_south = world:worldToScreen(origin_position:offset(0, PROBE_DISTANCE))
end
```

---

## 2. Comments, Voice, and Tone (Developer-Focused, No Literature)

- **Developer-first, direct, concise, and scannable.** Strip out narrative prose, metaphors, philosophy, conversational filler, and rhetorical questions.
- **NO literature or storytelling.** Do not write essays, personal reflections, or poetic/dramatic commentary in source files (e.g. do NOT write: `"One idea, and the whole addon is it..."` or `"Two of them at once add, which is the whole of the diagonals..."`).
- **Explain *what* or *why*, not obvious code.** Comments must be 1–2 short lines explaining non-obvious math, hardware/timing constraints, or lifecycle interactions.
- **No hedging, no selling.** Avoid words like `"simply"`, `"just"`, `"of course"`, `"powerful"`, `"note that"`.
- **Limits are facts, not apologies.** State technical boundaries plainly (e.g. `-- Requires player.move permission; returns nil if session is inactive`).
- **No historical clutter or changelogs.** Git tracks history. Document current truth only. Never leave commented-out dead code or notes like `"previously this was..."`.

---

## 3. Addon Structure and Manifest (`manifest.json`)

Every addon resides in its own top-level directory:
```text
<addon-id>/
  manifest.json      # Metadata, configuration, permissions, and network hosts
  main.lua           # Lua entry point
  assets/            # Custom assets (images, sounds) loaded via hafen.asset()
```

### Manifest Schema & Rules:
```json
{
  "id": "my-addon",
  "name": "My Addon Name",
  "version": "1.0.0",
  "author": "Author",
  "description": "Short, clear developer-focused description.",
  "api_version": "1.0",
  "files": [
    "main.lua"
  ],
  "permissions": [
    "player.move"
  ],
  "network": {
    "hosts": [
      "api.example.com"
    ]
  },
  "dependencies": [],
  "optional_dependencies": []
}
```

- **`id`**: Must match the directory name exactly.
- **`api_version`**: Must be `"1.0"` (the current client generation).
- **`files`**: List of `.lua` source files to execute in sequential order on startup.
- **`permissions`**: Explicitly declare all protected permissions needed by the addon (e.g. `"player.move"`, `"player.speed"`, `"client.settings"`, `"http.get"`).
- **`network`**: Required if using network permissions (`http.*`, `websocket.*`, `voice.*`). Explicitly list permitted hostnames under `network.hosts`.

---

## 4. API Conventions (`hafen.*`)

Follow the engine's canonical API patterns:

### Getters, Setters, and Chaining (Arity)
- The API does not use `getXYZ` or `setXYZ` prefixes.
- **Calling with no arguments = Getter**:
  ```lua
  local current_title = window:title()
  local is_visible = window:visible()
  ```
- **Calling with arguments = Setter**: Returns the receiver object, enabling call chaining:
  ```lua
  window:title("Status Window")
    :size(200, 100)
    :position(50, 50)
    :visible(true)
  ```

### Subsystems and Sessions
- Global subsystems are zero-argument functions: `hafen.session()`, `hafen.event()`, `hafen.timer()`, `hafen.client()`, `hafen.store()`, `hafen.log()`.
- Character/world subsystems require an active `Session` handle:
  ```lua
  local current_session = hafen.session():current()
  if current_session then
    local player_subsystem = current_session:player()
    local world_subsystem = current_session:world()
    local ui_subsystem = current_session:ui()
  end
  ```

### Collections and Queries
Standard collection query methods:
- `:list(filter?)` ➔ returns array of matching elements.
- `:count(filter?)` ➔ returns integer count.
- `:find(filter)` ➔ returns first matching element or `nil`.
- `:get(id)` ➔ returns element by key/id or `nil`.

Filters can be substring identifiers (e.g. `"terobjs/tree"`) or predicate functions:
```lua
local nearby_trees = world:gob():within(30, function(game_object)
  return game_object:resource():find("terobjs/tree") ~= nil
end)
```

### Strict Boolean Types
Boolean parameters require strict `true` or `false`. Non-boolean types (`1`, `0`, `"true"`, `nil`) will raise a runtime error:
```lua
window:visible(true)  -- Correct
window:visible(1)     -- ERROR: raises type mismatch
```

### 1-Based Indexing
All array indices, grid coordinates, and inventory slots in Lua are 1-based.

### Event Handling & Subscriptions
- Use `PascalCase` for client engine event keys (`SessionEnteredWorld`, `SessionSelected`, `Clicked`, `Added`, `Removed`, `Changed`).
- Calling `:on(event_name, callback)` returns a `Subscription` handle.
- Cancellation and destruction:
  - Subscriptions: `subscription:off()`
  - UI widgets created by addon: `widget:destroy()`
  - In-flight requests: `request:cancel()`

### Live Handles vs. Snapshots
- **Live Handles (`Gob`, `Widget`, `Session`)**: Maintain live references to engine state. If the entity despawns or closes, check `handle:exists()`.
- **Data Snapshots (`Position`, `MeterInfo`, `BuffInfo`)**: Plain, immutable Lua tables representing values at a specific instant.

---

## 5. Lua Sandbox & Execution Budgets

Addons run in a sandboxed Lua 5.2 environment (via LuaJ):

### Blocked APIs
- Standard I/O and process execution: `io.*`, `os.execute`, `os.exit`, `os.getenv`, `os.remove`, `os.rename`, `os.tmpname`.
- Dynamic code evaluation: `load`, `loadfile`, `dofile`, `loadstring`.
- Module loading: `require`, `package`, `module`.
- Threading/debugging: `debug.*`, `coroutine.*`.
- Direct Java reflection or Java bridge calls.

### Permitted APIs
- Safe standard libraries: `string`, `table`, `math`.
- Safe time functions: `os.time`, `os.clock`, `os.date`, `os.difftime`.
- Safe built-in functions: `pairs`, `ipairs`, `next`, `type`, `tostring`, `tonumber`, `pcall`, `xpcall`, `error`, `assert`, `select`.
- Client globals: `hafen`, `ADDON.id`, `ADDON.dir`.
- Local assets: load images/sounds via `hafen.asset()`.
- Persistent storage: `hafen.store():var("settings")` or session-scoped `session:store():var("settings")`.

### Engine Execution Budgets
- **Instruction Budget**: Maximum **10,000,000 Lua instructions** per single callback. Loops exceeding this budget terminate with an error to prevent client freezing.
- **Tick Budget**: Maximum **~10ms** execution time per frame. Sustained consumption (> 10ms for 30 consecutive frames) triggers automatic disablement by the watchdog.

---

## 6. Pre-Commit Quality Checklist for Addons

Before committing any Lua addon code:
1. [ ] **No single-letter variables**: Verify no `local s =`, `local w =`, `local p =`, `local g =`, `function(ev)`, `function(cb)`, etc. exist.
2. [ ] **No literary commentary**: Verify comments are direct, technical, and concise (no storytelling, philosophy, or conversational filler).
3. [ ] **Strict booleans**: Verify boolean setters receive literal `true` or `false`.
4. [ ] **Manifest validation**: `id` matches directory name, `api_version` is `"1.0"`, required `permissions` are declared.
5. [ ] **No blocked sandbox calls**: Verify absence of `require`, `io`, `os.execute`, etc.
6. [ ] **Lifecycle cleanup**: Subscriptions and timers are ended appropriately (`:off()`, `:destroy()`).
