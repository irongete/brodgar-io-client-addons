# Translations

Shows the client in another language, and lets you build that language yourself while you play.

## Choosing a language

**Options ▸ AddOns ▸ Translations ▸ Language.** `English` is the client's own text; every other entry is a
language made with this addon. The choice is remembered between sessions.

## Making a translation

1. In **Options ▸ AddOns ▸ Translations**, tick **Translation helper** and press **Open the translator**.
2. In the translator window, type a name in **New language** — `es`, for instance — and press **Add**.
3. Play. Every text the client shows that your language does not cover yet appears in the list, with the
   place it was shown in: `[button] Cancel`, `[window.title] Inventory`, `[tooltip] Quality: 23`. Open the
   windows you want to translate, hover over items, right-click for menus.
4. Click a row, type the translation and press Enter. The text changes on screen right away and the next
   row is selected.

Translations are saved as you go. The list of pending text is not: after a restart it fills up again as
you play.

## The translator window

- **Language** — the language you are viewing and editing, the same one as the option.
- **Show** — which rows to list: **Pending**, **Translated**, **Ignored** or **All**.
- **Filter** — only the rows containing this text. The list shows up to 500 rows, so use it when there are
  more.
- **New language** and **Add** — make a language. **Delete language** removes the current one with all its
  translations, and asks first.
- **Save**, or Enter — saves the translation of the selected row. **Delete** removes it and the text goes
  back to English.
- **Ignore** and **Restore** — hide a row you do not want to translate, until the next restart.
- **Match** and **Pattern** — for a text that changes every time. See below.

## Texts that change every time

Some texts carry a name or a number: `Irongete is now online.`, `Quality: 23`. A plain translation only
matches one exact text, so those want a pattern:

1. Select the row and press **Pattern**. **Match** is filled with the text, ready to edit.
2. Replace the part that changes with a group: `(.*)` for anything, `(\d+)` for a number, `(\w+)` for one
   word — `(.*) is now online\.`
3. Write the translation with `%1$s` where the first group goes, `%2$s` for the second, in any order:
   `%1$s se ha conectado.` Press Enter.

A pattern has to match the whole text. Patterns are listed in the **Translated** and **All** views between
slashes; select one to edit or delete it. If the client refuses a pattern, nothing is saved and the line
at the bottom of the window says why.

## Notes

- Text written by players — chat, names, speech bubbles — is never translated or listed.
- Tooltip rows and chat lines are listed with their formatting codes. Keep the codes and translate the
  words inside them.
- Translating only changes what you see. Other addons go on reading the client's English text, so they go
  on working.
- With another translation addon active at the same time, some texts may not reach this list. Collect with
  this addon alone.
- The client needs a font that has the characters of your language. The **Themes** addon can provide one.
- To ship a language as an addon of its own, see the
  [translating guide](https://irongete.github.io/brodgar-io-client/addons/guides/translating.html).
