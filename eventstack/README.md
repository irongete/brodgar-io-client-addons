# EventStack

A developer tool: a live log of what the client does, newest line first. Every message it sends, every
update it receives, every event on its bus, every widget coming and going, and every control somebody
pressed — all in one list, narrowed by whatever you are chasing, with one click for what a line carried.

It only watches. Nothing here cancels, rewrites or resends anything.

## Usage

1. Type `:eventstack` at the console to open the window, or assign a key in
   **Options ▸ Game ▸ Keybindings ▸ EventStack ▸ `toggle`**.
2. Tick the sources you want recorded along the top: **out** for what the client sends, **in** for what
   arrives, **bus** for events, **widget** for widgets opening and closing, and **ui** for the client's
   own controls being used. Unticking one stops the recording there and then.
3. Narrow what you are reading with the **source**, **session**, **widget** and **event** dropdowns, and
   with **word**, which matches anywhere in the line. Each dropdown fills itself from what has actually
   arrived, so nothing has to be known in advance.
4. Click a line for what it carried — and for the subscription that would catch the same thing in an
   addon of your own, spelled for the door it came through.

**pause** stops the list moving so you can read it; the sources go on recording underneath. **log**
writes the picked line whole to the console, where the text can be selected and copied, and **clear**
empties the list. The counter says how many lines your filters matched, of how many are held.

## Notes

- **at login** records from the moment the addon loads rather than from the moment you open the window,
  which is how you catch what happens during a login.
- A key for **pause** is worth assigning: the line you want is usually going past while you are reaching
  for the mouse.
- A character that enters the world while the sources are open is picked up on its own.
