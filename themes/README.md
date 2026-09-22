# Themes

Changes how the client looks: window frames, buttons, fields, tooltips, fonts, colours and the HUD plates.
Four themes ship with the addon, and picking one installs it at once.

## Usage

1. Open **Options ▸ AddOns ▸ Themes**. The dropdown lists every theme it can find.
2. Pick one. The client takes the new look straight away, and the choice is kept across restarts.

Disabling the addon gives the client's own look back.

## The themes it ships

- **default** — the client's own look. Installing it changes nothing.
- **simple** — the client's own look with no blackletter: plain box frames and a serif face.
- **hellokitty** — pink frames on a plum field, bow close buttons and heart wallpaper.
- **cyberpunk** — neon on near-black: cyan rules, magenta accents, corner brackets and a monospaced face.

## Notes

- A theme only names the parts it wants to change. Anything it leaves alone keeps the client's own look.
- A theme the client cannot read is refused whole, and the client keeps its own look rather than a half
  applied one.
- `hellokitty` and `cyberpunk` also dress the **Actionbars** and **Simple Chat** addons.

## Making one of your own

A theme is a JSON file in the addon's `themes/` folder, named in `themes/index.json`, and `default.json`
lists every part you can name with the client's own value beside it — so the way to start is to copy that
file and change what you want. Art of your own ships in the same folder and is named by path, drawn at the
size of the surface it replaces so it scales with the interface.

What a key can name and what a rule can say is in the
[theming guide](https://irongete.github.io/brodgar-io-client/addons/guides/theming.html).
