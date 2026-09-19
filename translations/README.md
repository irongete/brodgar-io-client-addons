# Translations

Shows the client in another language, and lets you build that language yourself while you play.

## Choosing a language

Options ▸ AddOns ▸ Translations ▸ **Language**. `English` is the client's own text. Any other entry is a
language created with this addon. The choice is remembered between sessions.

## Creating a translation

1. In Options ▸ AddOns ▸ Translations, tick **Translation helper** and press **Open the translator**.
2. In the translator window, type a name in **New language** (for example `es`) and press **Add**.
3. Play. Every text the client shows that your language does not translate yet appears in the list, with
   the place it was shown in: `[button] Cancel`, `[window.title] Inventory`, `[tooltip] Quality: 23`. Open
   the windows you want to translate, hover over items, right-click for menus.
4. Click a row, type the translation in the text field and press Enter. The text changes on screen right
   away, and the next row is selected.

Translations are saved as you go. The list of pending text is not: after a restart or a `:reload` it fills
up again as you play.

## The translator window

| Control | What it does |
|---|---|
| **Language** | The language you are viewing and editing. Same as the option. |
| **Show** | Which rows to list: **Pending** (not translated yet), **Translated**, **Ignored** or **All**. |
| **Filter** | Only rows containing this text. |
| **New language** / **Add** | Create a language. |
| **Delete language** | Delete the current language with all its translations. Asks for confirmation. |
| **Match** | Regular expression for a pattern (see below). Empty for a normal translation. |
| **Pattern** | Fill **Match** with the selected text, ready to turn into a pattern. |
| **Save** (or Enter) | Save the translation of the selected row. |
| **Delete** | Remove the translation of the selected row. The text goes back to English. |
| **Ignore** / **Restore** | Hide a row you do not want to translate, until the next restart or `:reload`. |

The list shows up to 500 rows. Use the filter if there are more.

## Patterns

Some texts contain a name or a number that changes every time (`Alistar is now online.`, `Quality: 23`).
A normal translation only matches one exact text, so use a pattern instead:

1. Select the row and press **Pattern**. **Match** is filled with the text, with special characters
   escaped: `Alistar is now online\.`
2. Replace the part that changes with a group: `(.*)` for anything, `(\d+)` for a number, `(\w+)` for one
   word: `(.*) is now online\.`
3. Write the translation with `%1$s` where the first group goes (`%2$s` for the second, in any order):
   `%1$s se ha conectado.` Press Enter.

The pattern must match the whole text. Patterns are Java regular expressions. They are listed in the
**Translated** and **All** views as `[chat.system] /(.*) is now online\./`; select one to edit or delete it.
If the client rejects a pattern (an unclosed parenthesis, a `%2$s` with only one group), nothing is saved
and the status line at the bottom says why.

## Where translations are stored

In `savedata/translations/translations.sqlite`, next to the client. To ship a language as an addon of its
own, see the client's [translating guide](https://github.com/irongete/brodgar-io-client/blob/HEAD/docs/addons/guides/translating.md).

## Good to know

- Text written by players (chat, names, speech bubbles) is never translated or listed.
- Tooltip rows and chat lines are listed with their formatting codes (`$col[...]{...}`, `$b{...}`). Keep the
  codes and translate the words inside them.
- Translating only changes what you see. Other addons keep reading the client's English text, so they keep
  working.
- If another translation addon is active at the same time, some texts may not appear in this list. Collect
  with this addon alone.
- The client needs a font with the characters of your language. A [theme](../themes/README.md) can provide
  one.
