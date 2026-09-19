-- Translations: displays the client in the language picked in Options > AddOns > Translations. With the
-- translation helper on, every string the language does not name yet is collected while you play, and the
-- translator window is where each one is translated and seen on screen the moment it is saved.
--
-- The manifest runs the files in order into one environment; each adds its module under `Translations`:
--   config.lua     constants (this file)
--   regex.lua      a matcher for the catalogue's patterns, so the list knows which rows a pattern answers
--   store.lua      the addon's file: languages, entries and patterns
--   options.lua    the two options and the page on Options > AddOns > Translations
--   catalogue.lua  the installed language: its document, the lookups, and the strings collected this session
--   rows.lua       the rows of the list, and which of them the view and the filter keep
--   languages.lua  picking, adding and deleting a language
--   window.lua     the translator window
--   main.lua       the harvest timer, the helper option and load

Translations = {}

local Config = {}
Translations.Config = Config

Config.ENGLISH = "English" -- the client's own words: no catalogue installed, nothing collected
Config.VIEWS = { "Pending", "Translated", "Ignored", "All" }
Config.MAX_ROWS = 500 -- the listbox takes 4096; past this the status line asks for a narrower filter
Config.RESET_MISSES_AT = 384 -- reinstall before the client's 512-pair miss set fills and stops recording

Config.WINDOW_WIDTH = 600 -- pinned, so a long string clips instead of widening the window
Config.LIST_HEIGHT = 260
Config.SOURCE_WIDTH = 90 -- bytes of the source line that fit the window
Config.STATUS_WIDTH = 110 -- bytes of the status line that fit the window
Config.BUTTON_WIDTH = 70
Config.ADD_WIDTH = 50
Config.LANGUAGE_BUTTON_WIDTH = 120
Config.OPEN_BUTTON_WIDTH = 150
Config.GAP = 6

-- What a player wrote is never collected: these surfaces are drawn as they are.
Config.PLAYER_TEXT_SURFACES = { "chat", "chat.mine", "chat.private", "chat.party", "world.nick", "world.speech" }

-- The window and the options page are drawn by the same client they watch, so their captions reach the
-- catalogue like any other label. These are skipped when collecting, by surface; a language name is skipped
-- wherever it is drawn. Keep in step with the captions window.lua and options.lua draw.
Config.OWN_CAPTIONS = {
    default = {
        "Language", "New language", "Show", "Filter", "Match", "Pick a row", "collecting",
        "Pending", "Translated", "Ignored", "All", Config.ENGLISH,
        "Translation helper: collect the strings the language does not name yet",
        "Delete this language and every translation it holds?",
    },
    button = {
        "Pattern", "Save", "Delete", "Ignore", "Restore", "Add", "Delete language", "Keep",
        "Open the translator",
    },
    ["window.title"] = { "Translator" },
}

-- The rows, the source line and the status line change all the time and would fill the miss set, so the
-- installed catalogue names them by shape (drawn as themselves) and the same shapes are skipped when
-- collecting. Keep in step with Rows.ofString, Rows.ofPattern and the status line in window.lua.
Config.OWN_LINE_PATTERNS = {
    { surface = "default", match = "\\[(\\*|[a-z]+(?:\\.[a-z]+)*)\\] (?s)(.*)", text = "[%1$s] %2$s" },
    { surface = "default", match = "(\\d+) pending(?s)(.*)", text = "%1$s pending%2$s" },
}
