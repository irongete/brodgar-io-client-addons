# Simple Chat

Replaces the client's chat window with a movable, resizable window whose channels are tabs across the top.
The client's chat is hidden while the addon runs and given back when it is disabled or reloaded.

## Use

| Action | Effect |
|---|---|
| `:simplechat`, the `toggle` hotkey, or the **Chat** button on the hotkey belt | hides or shows the window of the character on screen |
| click a tab | selects that channel |
| click the **×** on the selected private tab | closes that conversation, as the client's own X does |
| drag the body | moves the window |
| drag the bottom-right corner | resizes it |
| wheel over the lines | scrolls back; a scrolled-up view stays put while new lines arrive |
| Enter in the line at the bottom | sends the line to the selected channel |
| Enter on the **System** tab | runs the line as a console command (a leading `:` is dropped) |

Position and size are saved per account. The window is kept whole inside the screen.

**Suggested key: `Ctrl+C`**, assigned in Options ▸ Game ▸ Keybindings ▸ Simple Chat ▸ `toggle`. Addon hotkeys
start unbound. Once assigned, the client's own `chat-toggle` (also `Ctrl+C`) yields the key while the
assignment stands; nothing in the client's settings is written, and the client gets the key back when the
addon is disabled or removed.

## Tabs and lines

- One tab per channel, in the client's order, named as the client names it. The selected tab is lit; a tab
  with unread lines is amber. Names too long are cut with an ellipsis, measured against the font drawn.
- The selected private tab carries a × at its right end; the name gives it room.
- Tabs share the width down to a minimum; the ones that do not fit are hidden until the window is wider.
- Lines are drawn newest at the bottom, wrapped to the window, in the colour they carry (a speaker's colour,
  your own lines, client errors), with the speaker's name in front. Markup in a line is honoured.

## The client's chat

- Hidden once the window has laid itself out, for every character that enters the world.
- `Ctrl+C` and the belt's Chat button reopen the client's chat directly: its toggle bypasses the addon hide
  layer, which covers only the client's windows. The addon hides it again on the same tick, before the frame
  is drawn, and the keyboard focus the key moved into it is dropped. So until `Ctrl+C` is assigned to
  `toggle` the key does nothing; the belt button toggles this window.
- Given back on Disable as it was found: a chat collapsed before the addon took it stays collapsed.

## Permissions

| Key | Used for | Without it |
|---|---|---|
| `chat.send` | sending the entry's line to a channel | everything is shown; sending is refused and logged |
| `console.run` | the System tab's line — every console command, `:lua` included, which runs outside the addon sandbox | the tab shows everything; running is refused |
| `widget.send` | closing a private conversation: `close` sent from the conversation's own widget, the message the client's X sends | the × is drawn; closing is refused and logged |

## Theming

Every surface is declared with `widget:stock`, so a theme rule overrides it per property:

| Selector | Surface |
|---|---|
| `[name=simple-chat/panel]` | the window's field (background only) |
| `[name=simple-chat/frame]` | the frame: three widgets sharing one nine-slice (see below) |
| `[name=simple-chat/log]` | the rectangle the lines are laid out in; bare by default, so a `bg` is a wash behind them |
| `[name^=simple-chat/tab]` | every tab but the selected one; `[name=simple-chat/tab1]` is the first |
| `[name=simple-chat/selected]` | the selected tab: one plate, moved under whichever tab is being read |
| `[name^=simple-chat/joint]` | the two corners joining the frame to the selected tab |
| `[name=simple-chat/sizer]` | the resize corner |

The selected tab is a widget of its own because a rule names what a widget *is*, never the state it is in: a
theme that wants the tab being read to look different names `selected`. While it stands on a tab, that tab's
own widget is hidden. A theme with a frame of its own will want the joints out of the way — a fully
transparent `bg` paints nothing there.

The names and the lines are drawn by the addon, in the font a rule on their widget says (`font` on `log`,
`tab` and `selected` reaches them) and in colours of its own: a `color` in a rule composes with those tints
rather than replacing them, so a theme sets the font and leaves the colour.

Defaults: the frame is `gfx/hud/wnd`; the field is the action bars' colour, `{43, 51, 44, 127}`. `tab.png` and
`tab-on.png` are `gfx/hud/wnd`'s corners and edge runs at design scale, sliced 8/8/8/8 and 8/8/8/1: the
selected tab has no bottom edge and runs down to the frame. The frame is drawn through three clip boxes that
leave the selected tab's width of its top edge undrawn (the field is translucent, so the run cannot be painted
over); `joint-l.png` and `joint-r.png` are the corners where the top run turns up into the tab's sides.
`sizer.png` is the three strokes across the corner, as the client's own sizer draws them.

## Files

| File | Holds |
|---|---|
| `layout.lua` | the `SimpleChat` table and the constants |
| `clientchat.lua` | hiding the client's chat, keeping it hidden, giving it back; the belt button; closing a private conversation |
| `tabs.lua` | the tabs, the selected tab's plate and the frame cut |
| `log.lua` | the lines |
| `window.lua` | one window per login: build, layout, drop |
| `main.lua` | events, `:simplechat`, the hotkey |
