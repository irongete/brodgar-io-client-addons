# Multi-Session

Manages multiple character sessions with hotkeys, quick switching, ground selection circles, and account ordering preferences.

| You do | It does |
|---|---|
| press a row's name | hands the screen to that character |
| press a row's `X` | logs that character out |
| press a saved session button | connects that remembered account in the background |
| press `New session` | goes to the client's login screen, with every character still logged in behind it |
| press the `Select next session` hotkey | goes to the next login, and round |
| press the `Select character` hotkey, then click | the pointer becomes a hand; click a character (its model or its base) to go to it |
| press the `Focus selection` hotkey | centres the view on your character — on the `rts` camera |
| look at the map | a disc of coloured ground with a solid line round it under every character |

## Options & Account Sorting

Configurable in **Options ▸ AddOns ▸ Multi-Session**:

* **Sort accounts by name** (enabled by default): Automatically orders connected and saved accounts alphabetically.
* **Manual account order**: When "Sort accounts by name" is unchecked, this list enables and allows manually rearranging saved accounts using `Up` and `Down` buttons. When automatic sorting is checked, this list is disabled and grayed out.

## Logging another account in

`New session` shows the client's own login screen, which is live behind every session. **Nothing is logged out**: your characters go on running, and a row of this window brings you back to one whether or not you logged anything in.

*Suggested keys — assign them in Options ▸ Keybindings ▸ Multi-Session:* `Ctrl+Tab` for **Select next session**, `Ctrl+Q` for **Select character**, `Ctrl+Space` for **Focus selection**.

## Permissions

* `session.close` — log out any of your characters.
* `session.add` — log in remembered accounts saved by the login screen.

## Window Position

Window coordinates are persisted in `hafen.store():var("window")` across restarts and account changes.
