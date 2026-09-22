# Actionbars

Replaces the client's single action bar with up to twelve of your own, laid out wherever you want them,
flat or upright. The server keeps 144 belt slots per character; the client shows twelve of them at a time
and pages between them. This addon puts that bar away and lets you have every page on screen at once.

## Usage

1. Open **Options ▸ AddOns ▸ Actionbars**. There is a row per bar, twelve in all, and each row sets that
   bar to **off**, **flat** or **upright**, with a slider beside it for how many buttons it shows, 1 to 12.
2. Set a bar to flat or upright and it appears in the middle of the screen. Drag it where you want it: the
   frame, the gaps between the buttons and any empty button all pick the bar up, so only a button with
   something in it keeps its click.
3. Drag an action onto a button to put it there. Left-click fires it, right-click empties it, and resting
   the pointer on one names what is in it.

Each bar is one page of your belt: Actionbar2 is always slots 13–24, Actionbar3 always 25–36, and so on.
Turn a bar off and back on and it comes back with the same slots, the same keys and the place you left it.

**Actionbar1 is the one that pages.** It stands in for the bar the client draws, so it shows whichever page
you are on and the client's page keys (`Alt+1`–`Alt+0`) still turn it. It cannot be switched off.

## Keys

Every button has a hotkey of its own in **Options ▸ Keybindings ▸ Actionbars**, named `Actionbar1 slot 1`,
`Actionbar1 slot 2` and so on. They start unbound, like every addon hotkey — the assignment is yours.

While the addon runs, the client's own **Action bar** section comes off the keybindings panel, so the bars
are found in one place only. Its keys go on working: `1`–`0` press the first ten buttons of the page you
are on, and `Alt+1`–`Alt+0` turn the page. Assign the same key to an `Actionbar1 slot …` row and yours
takes over.

In combat, `1`–`5` and `Shift+1`–`5` are the client's combat-move keys and a combat window is offered a
key before any bar is. Bind your bar elsewhere if you fight with it.

## Options

**Options ▸ AddOns ▸ Actionbars**:

- **A row per bar** — off, flat or upright, and how many buttons it shows. A shorter bar starts from its
  first slot; the rest keep their contents and their hotkeys still fire.
- **Reset bars position** — puts every bar back in the middle of the screen, one under the next, for every
  character in the world. Use it when a bar has ended up off the edge after a change of interface scale or
  window size, where there is nothing left on screen to drag.

## Notes

- Every character has their own bars: which are on, which way they stand, how many buttons and where each
  one is. A character you have never played starts with Actionbar1 alone, flat, in the middle.
- Twelve bars is every slot there is, which is why there is no thirteenth row.
- What is in the slots belongs to the server and is never touched: turning a bar off leaves its contents
  alone, and disabling the addon gives the client's own bar back where it was.
- An entry another addon added to the action menu can be dropped on a bar. The slot is held for it until
  that addon removes the entry or is disabled, and the server's own content underneath comes back.
