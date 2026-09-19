# Themes

Changes how the client looks: window frames, buttons, fields, tooltips, fonts, colours and the HUD plates.
A theme is a JSON file; this addon ships four and installs the one you pick.

| Theme | Look |
|---|---|
| `default` | the client's own look. Installing it changes nothing |
| `simple` | the client's own look with no blackletter: plain box frames and a serif face |
| `hellokitty` | pink 9-slice frames on a plum field, bow close buttons, heart wallpaper |
| `cyberpunk` | neon on near-black: cyan rules, magenta accents, corner brackets, a monospaced face |

## Picking a theme

**Options ▸ AddOns ▸ Themes** holds one dropdown with every theme, in the order of `themes/index.json`,
each listed by its file name minus `.json`. It starts on `default`, which is the client's own look. Picking
one installs it at once, and the choice is kept across restarts. Disabling the addon gives the client's own
look back.

## Adding a theme

Drop `mytheme.json` into `themes/`, name it in `themes/index.json`, and `:reload`:

```json
{ "themes": ["default.json", "mytheme.json"] }
```

## Writing a theme

```json
{
  "name": "Ink",
  "rules": {
    "*":            { "font": { "builtin": "sans", "size": 11 } },
    "window.frame": { "bg": { "color": { "r": 26, "g": 26, "b": 28, "a": 240 } }, "padding": 6 },
    "tooltip":      { "border": { "color": { "r": 200, "g": 160, "b": 60 }, "width": 1 } }
  }
}
```

`rules` is the client's stylesheet written as JSON: each key names a surface, each value the properties it
takes. Anything a theme does not name keeps the client's own look, so a file holding one key and one colour
is a valid theme. **What a key can name, what a rule can say, and how to reach another addon's widgets is
in the [theming guide](https://irongete.github.io/brodgar-io-client/addons/guides/theming.html).**

What is specific to this addon:

- **Start from `default.json`.** It lists every surface key and every property each one accepts, with the
  client's own value where the client sets one and `null` where it does not. Copy it and change what you
  want; a `null` is the same as leaving the property out. Its `treeKeys` and `shapes` blocks are reference
  material for the editor, not read by the client.
- **Art of your own** ships in this folder and is named by path: `{ "asset": "themes/mytheme/panel.png" }`.
  Draw a picture at the size of the surface it replaces, in design pixels, so it scales with the interface.
  `hellokitty.json` and `cyberpunk.json` show the properties in use, and dress the **Actionbars** and
  **Simple Chat** addons through their named widgets.
- **A broken theme is refused whole.** A rule the sheet rejects is reported in the log with its key and
  property, and the client keeps its own look.
