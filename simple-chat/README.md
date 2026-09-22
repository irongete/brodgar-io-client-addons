# Simple Chat

Replaces the client's chat with a movable, resizable window whose channels are tabs across the top. The
client's chat is hidden while the addon runs, and given back as it was found when the addon is disabled.

## Use

| Action | Effect |
|---|---|
| `:simplechat`, the `toggle` hotkey, or the **Chat** button on the hotkey belt | hides or shows the window |
| click a tab | selects that channel |
| click the **×** on the selected private tab | closes that conversation |
| drag the body | moves the window |
| drag the bottom-right corner | resizes it |
| wheel over the lines | scrolls back; a scrolled-up view stays put while new lines arrive |
| Enter in the line at the bottom | sends the line to the selected channel |
| Enter on the **System** tab | runs the line as a console command (a leading `:` is dropped) |

Position and size are saved per account, and the window is kept whole inside the screen.

## The key

**Suggested key: `Ctrl+C`**, assigned in Options ▸ Game ▸ Keybindings ▸ Simple Chat ▸ `toggle`. Addon hotkeys
start unbound, so until you assign it the key does nothing and the belt's Chat button toggles this window.
Once assigned, the client's own `chat-toggle` yields the key while the assignment stands; nothing in the
client's settings is changed, and the client gets the key back when the addon is disabled or removed.

## Tabs

One tab per channel, in the client's order and under the client's name for it. The selected tab is lit, and a
tab with unread lines is amber. The selected private tab carries a × to close the conversation. Tabs share the
width down to a minimum; the ones that do not fit are hidden until you make the window wider.

Lines arrive newest at the bottom, wrapped to the window, each in the colour it carries and with the
speaker's name in front.

## Permissions

| Key | Used for | Without it |
|---|---|---|
| `chat.send` | sending your line to a channel | everything is shown; sending is refused |
| `console.run` | the System tab's line — every console command, `:lua` included | the tab shows everything; running is refused |
| `widget.send` | closing a private conversation | the × is drawn; closing is refused |
