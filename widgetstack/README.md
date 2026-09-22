# WidgetStack

A developer tool: it shows the stack of widgets under your cursor, outlines the one you are hovering, and
hands you the selector that reaches it — the line you paste into an addon of your own.

## Usage

1. Type `:widgetstack` at the console to open the window, and again to close it.
2. Move the pointer over the interface. The window lists every widget under it, from the outermost down
   to the one a click would actually reach, and the hovered one is outlined on screen.
3. Click a row to open that widget's full details, and click a child inside those details to walk further
   in.
4. The panel at the bottom says what the hovered widget is — its role, its class, its own caption or
   text, its resource, and the window enclosing it — and then every selector that really matches it, most
   specific first, with how many widgets each one matches and which of them this is. The last line is
   ready to paste.

Assign a key to **freeze** in **Options ▸ Game ▸ Keybindings ▸ Widgetstack** — `Ctrl+Shift+F` is a good
one. It holds the stack still so you can move the pointer into the window to read and click it without
everything changing under you.

## Notes

- Clicking a row in the selector panel, or typing `:selector`, writes the whole report to the console,
  where the text can be selected and copied out of the client.
- Every selector offered has been resolved first and kept only if it really matches the hovered widget,
  so nothing is offered that does not work.
- Where a selector names that widget and nothing else, the line offered uses `match`; where it does not,
  it uses `matchAll` with the index, because `match` refuses an ambiguous answer rather than guessing.
- The widget under the pointer is the one a real click would hit, scroll offsets and odd shapes included.
