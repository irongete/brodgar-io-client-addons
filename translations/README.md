# Translations

Displays the client in the language you pick, and helps you write that language: with the **translation
helper** on, every string the language does not name yet is collected while you play, the **translator**
window is where you translate them one at a time — each one on screen the moment it is saved — and
**Export** prints the language as the JSON document
[`hafen.locale():load(doc)`](https://github.com/irongete/brodgar-io-client/blob/HEAD/docs/addons/api/locale.md)
takes, ready to ship as `<language>.json`.

## Pick the language

**Options ▸ AddOns ▸ Translations ▸ Language.** `English` is the client's own words; any other row is a
language kept in the addon's file, installed the moment it is picked. The pick survives reloads and
restarts.

## The helper

Off by default. Tick **Translation helper** on the same page and **Open the translator** comes alive — so
does `:translator`, and the `translator` key once you assign one in Options ▸ Game ▸ Keybindings ▸
Translations. With the helper off nothing is collected and the window cannot be opened.

1. **Pick a language**, in the window or on the options page. Its catalogue is installed: the client
   displays what the language names, and everything it does not name is drawn in English and **recorded**.
2. **Play.** Every string a routed surface draws — a button, a window title, a menu petal, a tooltip row, a
   system line — lands in the list once, keyed by the surface it reached and spelt exactly as the client
   offered it. Open the windows you mean to translate, hover the items, right-click for the menus.
3. **Translate.** Pick a row: the surface and the English are shown, and the entry holds the English to
   edit. Type the translation and press **Enter** (or **Save**): the catalogue is reloaded on the spot, the
   string re-renders in your words wherever it is on screen, the row leaves *Pending*, and the next one is
   picked so you can go on typing.
4. **Check it live.** Switch the language in the dropdown and the whole client follows — every saved entry
   of that language in force, everything else in English.

The rows are `[surface] text`. **Show** picks the view — *Pending* (seen, and nothing answers it),
*Translated* (everything the language answers: its entries and its patterns, seen this session or not),
*Ignored*, *All* — and **Filter** narrows any view on a fragment of the row. The list holds the first 500
matches; the status line says when to narrow.

**The edit line shows what the catalogue says for the picked row**: an exact entry (Match empty, the entry
holding the translation), a pattern (Match holding its match, the entry its text), or nothing yet (Match
empty, the entry holding the English). **Save** writes what the line shows — Enter in either field — and
**Delete** removes it; a string still being drawn goes back to *Pending*. An empty **Save** changes nothing.

**Ignore** puts a string aside — a line carrying a player's name, a row carrying a number, anything not
worth an entry — and **Restore** (the same button, on an ignored row) brings it back. Ignoring hides for
the session; it never deletes.

### Languages

**New language** + **Add** (or Enter) creates a language under the name you typed — `es`, `pt-BR`,
`Español`, whatever you want the file called — and picks it, empty. A blank, a repeat (whatever the case)
and `English` are refused. **Delete language** asks first, in a window titled with the language: **Delete**
removes the language and **every translation it holds**, entries and patterns alike, and the client's own
words come back; **Keep** closes the window and changes nothing.

### Patterns

A line with a name or a number in it is a different string every time — `Alistar is now online.`,
`Quality: 23` — so no exact entry can name it, and a **pattern** names its shape instead:

1. Pick one of the rows and press **Pattern**: Match holds the English with every special character
   escaped — `Alistar is now online\.`.
2. Replace the part that varies with a **group**: `(.*)` anything, `(\d+)` a number, `(\w+)` one word,
   `(a|b)` one of two — `(.*) is now online\.`. The pattern has to match the **whole** string.
3. Write the translation in the entry with `%1$s` where the first group goes (`%2$s` the second, in any
   order your language wants): `%1$s se ha conectado.` Enter.

Every pending row the pattern answers leaves *Pending* on the spot, and a line with another name in it
never enters the list. The pattern has a row of its own in *Translated* and *All* — `[chat.system] /(.*) is
now online\./` — and picking a string it answers shows it too: Save there edits the pattern in place,
Delete removes it. A match the client cannot read (an unclosed `(`, a `%2$s` with one group) is refused on
the spot: nothing is written and the status line says why.

Patterns are Java regular expressions, resolved after every exact entry has missed and **in the order they
were written** — the first that matches answers. The list reads the usual regex on its own to decide what
leaves it (escapes, `.`, classes, groups, alternation, the quantifiers and their lazy forms, `(?s)` and
`(?i)`); a construction it does not read — a lookaround, a backreference — still works in the client, but
the rows it answers stay in the list this session.

### Export

**Export** prints the picked language as one line on the terminal the client was started from:

```text
[translations] es.json = {"text":{"button":{"Cancel":"Cancelar"}},"pattern":[{"surface":"tooltip","match":"Quality: (\\d+)","text":"Calidad: %1$s"}]}
```

What follows `es.json = ` is exactly the content of `es.json`: `text` keyed by surface and then by the
string the client would have drawn, `pattern` the ordered list, absent while there is none. The addon that
ships it is the whole of this:

```lua
local doc = hafen.json():parse(hafen.asset():get("es.json"):text())
hafen.locale():load(doc):install()
```

The in-game console clips the line at 500 characters; the terminal always has the whole of it.

## The file

Everything is in **`savedata/translations/translations.sqlite`**, written by the client: `languages` (one
row per language), `entries` (language, surface, source, translation) and `patterns` (language, position,
surface, match, text). A translation is in the file the moment it is saved. Nothing the list collected is in
it: the strings are held for the session, a `:reload` or a restart starts the list again from what the
client draws next, and a string put aside with *Ignore* is put aside until then. The list is shared by
every language while it lasts — a string collected while `es` was up is pending in `ru` too, until `ru`
names it.

## Options and keys

- Options ▸ AddOns ▸ Translations — **Language**, the **Translation helper** tick and **Open the translator**.
- `:translator` opens and closes the window; it comes back where you left it, and open if it was open.
- **translator** — the same, on a key. Suggested key: **Ctrl+T** — assign it in Options ▸ Game ▸
  Keybindings ▸ Translations.

## Notes

- **The addon's own text is never listed.** The window and the options page are drawn by the same client
  they watch, so their captions reach the catalogue like any other label: the fixed ones — *Language*,
  *Show*, *Filter*, *Match*, *Pattern*, *Save*, *Delete*, *Ignore*, *Restore*, *Add*, *Delete language*,
  *Export*, *Keep*, the view names, *Translator*, the language names — are skipped when collecting, and
  the rows, the source line and the status line, which change all the time, are named by their shape in
  the installed catalogue so they never miss at all. The one cost: a game string that is exactly one of
  those captions at the same surface is skipped too — write it into the file by hand.
- **Two catalogues stack, and the top one answers first.** While another addon's catalogue is installed
  above this one, a string it names never reaches the helper, as a translation or as a miss. Collect with
  this addon alone.
- A **tooltip row and a chat line are recorded as their marked-up source** (`$col[...]{...}`, `$b{...}`), not
  as the words drawn, because that is the string an entry has to spell. Translate inside the markup and
  leave the markup as it is.
- **What you type is what the entry takes.** Cyrillic needs the layout switched; Chinese needs the system
  IME to reach the client's window. The text drawn on screen is only as good as the font the client has for
  it: a face without the glyphs draws boxes, and a [theme](../themes/README.md) is where a face with them is
  installed.
- The catalogue changes what you **see** and nothing else: `w:text()`, a petal's name and everything an
  addon reads still answer the client's English, so the other addons keep working while a language is up.
