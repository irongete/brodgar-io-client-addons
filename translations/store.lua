-- The addon's file (savedata/translations/translations.sqlite): one row per language, its exact entries and
-- its ordered patterns. A translation is in the file the moment it is saved; the collected strings never are.

local Config = Translations.Config

local Store = {}
Translations.Store = Store

local store = hafen.store()

Store.settings = store:var("settings") -- windowOpen: whether the translator was open when the addon last ran

local languagesTable = store:table("languages")
    :column("name", "text")
    :key("name")
    :create()
local entriesTable = store:table("entries")
    :column("language", "text"):column("surface", "text"):column("source", "text"):column("translation", "text")
    :key("language", "surface", "source")
    :create()
local patternsTable = store:table("patterns")
    :column("language", "text"):column("position", "integer")
    :column("surface", "text"):column("match", "text"):column("text", "text")
    :key("language", "position")
    :create()

local languageNames = {} -- every language in the file, sorted
local languageNameSet = {} -- name -> true

local function readLanguages()
    languageNames, languageNameSet = {}, {}
    for _, row in ipairs(languagesTable:list("ORDER BY name COLLATE NOCASE")) do
        languageNames[#languageNames + 1] = row.name
        languageNameSet[row.name] = true
    end
end

function Store.isLanguage(name) -- a language in the file, spelt as stored
    return languageNameSet[name] == true
end

function Store.findLanguage(name) -- the stored spelling of a name, compared without regard to case
    for _, stored in ipairs(languageNames) do
        if string.lower(stored) == string.lower(name) then
            return stored
        end
    end
    return nil
end

function Store.languageRows() -- the dropdowns' rows: English first, then the languages
    local rows = { Config.ENGLISH }
    for _, name in ipairs(languageNames) do
        rows[#rows + 1] = name
    end
    return rows
end

-- A language's document, the shape hafen.locale():load(doc) takes:
-- { text = { [surface] = { [source] = translation } }, pattern = { { surface, match, text } } }
function Store.readDocument(language)
    local text = {}
    for _, row in ipairs(entriesTable:list("WHERE language = ?", language)) do
        if text[row.surface] == nil then
            text[row.surface] = {}
        end
        text[row.surface][row.source] = row.translation
    end
    local pattern = {}
    for _, row in ipairs(patternsTable:list("WHERE language = ? ORDER BY position", language)) do
        pattern[#pattern + 1] = { surface = row.surface, match = row.match, text = row.text }
    end
    return { text = text, pattern = pattern }
end

function Store.putEntry(language, surface, source, translation)
    entriesTable:put{ language = language, surface = surface, source = source, translation = translation }
end

function Store.removeEntry(language, surface, source)
    entriesTable:remove(language, surface, source)
end

function Store.writePatterns(language, patterns) -- the language's whole ordered list, in one write
    store:transaction(function()
        store:exec("DELETE FROM patterns WHERE language = ?", language)
        for position, member in ipairs(patterns) do
            patternsTable:put{ language = language, position = position,
                               surface = member.surface, match = member.match, text = member.text }
        end
    end)
end

function Store.addLanguage(name)
    languagesTable:put{ name = name }
    readLanguages()
end

function Store.deleteLanguage(name) -- the language and every translation it holds, in one write
    store:transaction(function()
        store:exec("DELETE FROM entries WHERE language = ?", name)
        store:exec("DELETE FROM patterns WHERE language = ?", name)
        languagesTable:remove(name)
    end)
    readLanguages()
end

readLanguages()
