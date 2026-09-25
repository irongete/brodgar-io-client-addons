# Simple Chat

Replaces the client's chat with a window you can move and resize, whose channels are tabs across the top.
The client's own chat is hidden while the addon runs and given back as it was found when you disable it.

## Usage

1. Press the **Chat** button on the hotkey belt to show or hide the window. You can also assign a key in
   **Options ▸ Game ▸ Keybindings ▸ Simple Chat ▸ `toggle`** — `Ctrl+C` is the one the client uses for its
   own chat, and assigning it here takes it over for as long as the assignment stands.
2. Click a tab to select a channel, and the **×** on a selected private tab to close that conversation.
3. Type in the line at the bottom and press Enter to send to the selected channel. On the **System** tab
   the line runs as a console command instead, with a leading `:` dropped if you type one.
4. **Drag the body** to move the window and **the bottom-right corner** to resize it. Where you put it and
   how big you made it are saved per account, and it is kept whole inside the screen.

## Notes

- There is one tab per channel, in the client's order and under the client's name for it. The selected tab
  is lit and a tab with unread lines is amber.
- Tabs share the width down to a minimum; the ones that do not fit are hidden until you widen the window.
- Lines arrive newest at the bottom, wrapped to the window, each in the colour it carries and with the
  speaker's name in front.
- The wheel scrolls back, and a view you have scrolled up stays put while new lines arrive.
- Nothing in the client's own settings is changed: the key goes back to the client's chat when the addon
  is disabled or removed.

## For bundles

An addon that lists `simple-chat>=1.1.0` in its `dependencies` can start the window somewhere else, from its
own file:

```lua
local chat = hafen.client():addons():get("simple-chat"):api()
if chat then   -- nil while the player has Simple Chat turned off
  chat.preset{
    place = {at = "bottomright", offset = {-8, -8}},   -- the corner it starts in, as a sheet anchor
    size = {width = 480, height = 260},                -- the size it starts at
  }
end
```

The numbers are screen pixels, so the window starts the same size whatever the player's interface scale. Both
only say where the window starts: once the player moves or resizes it, their place and size win.
