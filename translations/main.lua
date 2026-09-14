-- Translations: displays the client in the language picked in Options > AddOns > Translations. With the
-- translation helper on, every string the language does not name yet is collected while you play, and the
-- translator window is where each one is translated and seen on screen the moment it is saved.
--
-- A language is one catalogue document -- text and pattern, the shape hafen.locale():load(doc) takes --
-- kept as rows of the addon's own file: `languages` names it, `entries` holds its exact entries and
-- `patterns` its ordered patterns. Export prints the document as one JSON line on the terminal, ready to
-- be shipped as <language>.json.

local ENGLISH = "English" -- the client's own words: no catalogue installed, nothing collected
local VIEWS = { "Pending", "Translated", "Ignored", "All" }
local MAX_ROWS = 500 -- the listbox takes 4096; past this the status line asks for a narrower filter
local RESET_MISSES_AT = 384 -- reinstall before the client's 512-pair miss set fills and stops recording
local WINDOW_WIDTH = 600 -- pinned, so a long string clips instead of widening the window
local STATUS_WIDTH = 110 -- bytes of the status line that fit the window
local BUTTON_WIDTH = 70
local ADD_WIDTH = 50
local LANGUAGE_BUTTON_WIDTH = 120
local OPEN_BUTTON_WIDTH = 150
local GAP = 6

-- What a player wrote is nobody's to translate: these surfaces are drawn as they are and never collected.
local PLAYER_TEXT_SURFACES = { "chat", "chat.mine", "chat.private", "chat.party", "world.nick", "world.speech" }

-- The translator window and the options page are drawn by the same client they watch, so their captions
-- reach the catalogue like any other label and would be collected as strings to translate. The fixed ones
-- are skipped when collecting, by surface; a language name is skipped wherever it is drawn.
local OWN_CAPTIONS = {
    default = {
        "Language", "New language", "Show", "Filter", "Match", "Pick a row", "collecting",
        "Pending", "Translated", "Ignored", "All", ENGLISH,
        "Translation helper: collect the strings the language does not name yet",
        ":translator opens it too.", "A key for it: Options > Game > Keybindings > Translations.",
        "Delete this language and every translation it holds?",
    },
    button = {
        "Pattern", "Save", "Delete", "Ignore", "Restore", "Add", "Delete language", "Export", "Keep",
        "Open the translator",
    },
    ["window.title"] = { "Translator" },
}

-- The rows, the source line and the status line change all the time and would fill the miss set with
-- themselves, so the installed catalogue names them by their shape, drawn as themselves, and the same
-- shapes are skipped when collecting.
local OWN_LINE_PATTERNS = {
    { surface = "default", match = "\\[(\\*|[a-z]+(?:\\.[a-z]+)*)\\] (?s)(.*)", text = "[%1$s] %2$s" },
    { surface = "default", match = "(\\d+) pending(?s)(.*)", text = "%1$s pending%2$s" },
}

local function ownLineShape(surface, text)
    return surface == "default" and (string.find(text, "^%[[%a%.%*]+%] ") ~= nil
        or string.find(text, "^%d+ pending") ~= nil)
end

local ownCaptionSet = {} -- surface -> { caption = true }
for surface, captions in pairs(OWN_CAPTIONS) do
    ownCaptionSet[surface] = {}
    for _, caption in ipairs(captions) do
        ownCaptionSet[surface][caption] = true
    end
end

-- ---------------------------------------------------------------- the file

local store = hafen.store()
local settings = store:var("settings") -- windowOpen: whether the translator was open when the addon last ran

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
readLanguages()

local function languageRows() -- the dropdowns' rows: English first, then the languages
    local rows = { ENGLISH }
    for _, name in ipairs(languageNames) do
        rows[#rows + 1] = name
    end
    return rows
end

local function findLanguage(name) -- the stored spelling of a name, compared without regard to case
    for _, stored in ipairs(languageNames) do
        if string.lower(stored) == string.lower(name) then
            return stored
        end
    end
    return nil
end

-- The current language's document, read from the file when the language is picked and written back row by
-- row as it is edited: { text = { [surface] = { [source] = translation } }, pattern = { { surface, match, text } } }.
local function readDocument(languageName)
    local text = {}
    for _, row in ipairs(entriesTable:list("WHERE language = ?", languageName)) do
        if text[row.surface] == nil then
            text[row.surface] = {}
        end
        text[row.surface][row.source] = row.translation
    end
    local pattern = {}
    for _, row in ipairs(patternsTable:list("WHERE language = ? ORDER BY position", languageName)) do
        pattern[#pattern + 1] = { surface = row.surface, match = row.match, text = row.text }
    end
    return { text = text, pattern = pattern }
end

-- ---------------------------------------------------------------- the options

local options = hafen.client():options():addon()
local languageOption = options:text("language"):default(ENGLISH):add()
local helperOption = options:boolean("helper"):default(false):add()

-- ---------------------------------------------------------------- the state

local currentLanguage = nil -- the language installed, nil while English is displayed
local document = nil -- its document, nil while English is displayed

-- The list is not saved: only a translation is. What the client has drawn since the addon loaded is
-- collected again as you play, and a string put aside is put aside for this session.
local seen = {} -- every (surface, text) collected this session: seen[surface][text] = true
local ignored = {} -- the ones put aside, the same shape

local window -- the translator window, nil until it is built and after its X
local listbox, viewDropdown, filterEntry, windowLanguageDropdown, panelLanguageDropdown
local sourceLabel, statusLabel, matchRow, matchEntry, patternButton
local editRow, translationEntry, deleteButton, ignoreButton
local deleteLanguageButton, exportButton
local confirmWindow -- the "delete this language?" window, while it is up
local selected -- { surface, text } the string picked, or { surface, pattern } a pattern's own row
local shownRows, rowKeys = {}, {} -- the rows on screen, and each row's key
local lastMissCount = -1 -- the miss count the last harvest read, so an unchanged set is not walked
local refusal -- what the last :load(doc) said no to, for the status line

local function flagged(set, surface, text)
    return set[surface] ~= nil and set[surface][text] ~= nil
end

local function flag(set, surface, text, on)
    if on then
        if set[surface] == nil then
            set[surface] = {}
        end
        set[surface][text] = true
    elseif set[surface] then
        set[surface][text] = nil
    end
end

local function ownText(surface, text) -- drawn by this addon's own window or page: never collected
    return (ownCaptionSet[surface] ~= nil and ownCaptionSet[surface][text] == true)
        or languageNameSet[text] == true
        or ownLineShape(surface, text)
end

-- ---------------------------------------------------------------- the catalogue

-- What is installed: the document, plus what is not to be collected.
local function catalogue()
    local text = {}
    for surface, entries in pairs(document.text) do
        local copy = {}
        for source, translation in pairs(entries) do
            copy[source] = translation
        end
        text[surface] = copy
    end
    for surface, texts in pairs(ignored) do -- an ignored string is drawn as itself, and never misses
        if text[surface] == nil then
            text[surface] = {}
        end
        for source in pairs(texts) do
            if text[surface][source] == nil then
                text[surface][source] = source
            end
        end
    end
    local pattern = {}
    for index, member in ipairs(document.pattern) do
        pattern[index] = member
    end
    for _, surface in ipairs(PLAYER_TEXT_SURFACES) do
        pattern[#pattern + 1] = { surface = surface, match = "(?s)(.*)", text = "%1$s" }
    end
    for _, member in ipairs(OWN_LINE_PATTERNS) do
        pattern[#pattern + 1] = member
    end
    return { text = text, pattern = pattern }
end

local function reload() -- an installed catalogue says the new document at once
    if currentLanguage == nil then
        return true
    end
    local ok, failure = pcall(function() hafen.locale():load(catalogue()) end)
    if not ok then
        refusal = string.gsub(tostring(failure), "\nstack traceback:.*$", "")
        for _ = 1, 3 do -- the "@main.lua:162 " a bridge refusal is prefixed with
            refusal = string.gsub(refusal, "^@?.-%.lua:%d+:?%s*", "")
        end
        hafen.log():write("the " .. currentLanguage .. " catalogue was refused: " .. refusal)
    end
    return ok
end

local function translationOf(surface, text) -- the exact entry that answers the string: the surface's, then "*"'s
    if document == nil then
        return nil
    end
    local entries = document.text[surface]
    if entries and entries[text] then
        return entries[text]
    end
    entries = document.text["*"]
    return entries and entries[text] or nil
end

local compiledPatterns = {} -- match source -> the compiled pattern, or false where regex.lua reads none

local function patternIndexFor(surface, text) -- the first pattern of the language that answers the string, or nil
    if document == nil then
        return nil
    end
    for index, member in ipairs(document.pattern) do
        if member.surface == surface or member.surface == "*" then
            local program = compiledPatterns[member.match]
            if program == nil then
                program = regex.compile(member.match) or false
                compiledPatterns[member.match] = program
            end
            if program and regex.matches(program, text) then
                return index
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------- the rows

local function oneLine(text)
    return (string.gsub(text, "[\r\n]+", " "))
end

local function clip(text, limit) -- at most limit bytes, never cutting a UTF-8 character in two
    if #text <= limit then
        return text
    end
    local cut = limit
    while cut > 1 do
        local byte = string.byte(text, cut + 1)
        if byte == nil or byte < 0x80 or byte >= 0xC0 then
            break
        end
        cut = cut - 1
    end
    return string.sub(text, 1, cut) .. "..."
end

local function rowOf(surface, text)
    return "[" .. surface .. "] " .. oneLine(text)
end

local function patternRow(member) -- a pattern's own row: its match between slashes
    return "[" .. member.surface .. "] /" .. oneLine(member.match) .. "/"
end

local function knownStrings() -- the strings seen this session, and every string the language names, seen or not
    local all = {}
    for surface, texts in pairs(seen) do
        all[surface] = {}
        for text in pairs(texts) do
            all[surface][text] = true
        end
    end
    if document then
        for surface, entries in pairs(document.text) do
            if all[surface] == nil then
                all[surface] = {}
            end
            for source in pairs(entries) do
                all[surface][source] = true
            end
        end
    end
    return all
end

local function collect() -- the rows the view and the filter keep, sorted by surface then text
    local view = viewDropdown and viewDropdown:value() or "Pending"
    local needle = string.lower(filterEntry and filterEntry:value() or "")
    local all = knownStrings()
    local surfaces = {}
    for surface in pairs(all) do
        surfaces[#surfaces + 1] = surface
    end
    table.sort(surfaces)
    local rows, keys, total = {}, {}, 0
    local counts = { Pending = 0, Translated = 0, Ignored = 0, Patterns = 0 }
    local function keep(row, key)
        if needle == "" or string.find(string.lower(row), needle, 1, true) then
            total = total + 1
            if total <= MAX_ROWS then
                rows[#rows + 1] = row
                keys[row] = key
            end
        end
    end
    if document then -- the patterns first, in the order they answer in
        counts.Patterns = #document.pattern
        if view == "All" or view == "Translated" then
            for index, member in ipairs(document.pattern) do
                keep(patternRow(member), { surface = member.surface, pattern = index })
            end
        end
    end
    for _, surface in ipairs(surfaces) do
        local texts = {}
        for text in pairs(all[surface]) do
            texts[#texts + 1] = text
        end
        table.sort(texts)
        for _, text in ipairs(texts) do
            local state
            if flagged(ignored, surface, text) then
                state = "Ignored"
            elseif translationOf(surface, text) or patternIndexFor(surface, text) then
                state = "Translated"
            else
                state = "Pending"
            end
            counts[state] = counts[state] + 1
            if view == "All" or view == state then
                keep(rowOf(surface, text), { surface = surface, text = text })
            end
        end
    end
    return rows, keys, total, counts
end

-- The edit line shows what the catalogue says for the picked row: an exact entry (Match empty, the entry
-- holding the translation), a pattern (Match holding its match, the entry its text), or nothing yet (Match
-- empty, the entry holding the English). Save writes what the line shows; Delete removes it.
local function show(key)
    selected = key
    if key == nil then
        sourceLabel:text("Pick a row")
        matchEntry:value("")
        translationEntry:value("")
        ignoreButton:text("Ignore"):enabled(false)
        deleteButton:enabled(false)
        patternButton:enabled(false)
        return
    end
    if key.text == nil then -- a pattern's own row
        local member = document.pattern[key.pattern]
        sourceLabel:text(clip(patternRow(member), 90))
        matchEntry:value(member.match)
        translationEntry:value(member.text)
        ignoreButton:text("Ignore"):enabled(false)
        deleteButton:enabled(true)
        patternButton:enabled(false)
        return
    end
    local translation = translationOf(key.surface, key.text)
    local patternIndex = (translation == nil) and patternIndexFor(key.surface, key.text) or nil
    key.pattern = patternIndex -- the pattern that answers this string, if one does: Save edits it
    sourceLabel:text(clip(rowOf(key.surface, key.text), 90)) -- the row's own shape, which the catalogue names as itself
    if patternIndex then
        local member = document.pattern[patternIndex]
        matchEntry:value(member.match)
        translationEntry:value(member.text)
    else
        matchEntry:value("")
        translationEntry:value(translation or key.text)
    end
    ignoreButton:text(flagged(ignored, key.surface, key.text) and "Restore" or "Ignore"):enabled(true)
    deleteButton:enabled(translation ~= nil or patternIndex ~= nil)
    patternButton:enabled(true)
end

local function windowUp()
    return window ~= nil and window:exists()
end

local function refresh(note) -- note: what the status line says instead of the counts, this once
    if not windowUp() then
        return
    end
    local rows, keys, total, counts = collect()
    local same = (#rows == #shownRows)
    if same then
        for index = 1, #rows do
            if rows[index] ~= shownRows[index] then
                same = false
                break
            end
        end
    end
    if not same then
        local picked = listbox:value()
        listbox:rows(rows) -- replaces the set, and clears the pick with it
        shownRows, rowKeys = rows, keys
        if picked and keys[picked] then -- ...so it is put back where the row still stands
            listbox:value(picked)
        elseif picked then
            show(nil)
        end
    end
    local editing = currentLanguage ~= nil
    editRow:enabled(editing)
    matchRow:enabled(editing)
    deleteLanguageButton:enabled(editing)
    exportButton:enabled(editing)
    local line = counts.Pending .. " pending, " .. counts.Translated .. " translated, "
        .. counts.Patterns .. " patterns, " .. counts.Ignored .. " ignored"
    if total > MAX_ROWS then
        line = line .. " -- showing " .. MAX_ROWS .. " of " .. total .. ": narrow the filter"
    end
    if note then
        line = counts.Pending .. " pending -- " .. oneLine(note) -- the shape the counts line has
    end
    statusLabel:text(clip(line, STATUS_WIDTH))
end

local function pick(row) -- select a row as the user would, and show it
    if row and rowKeys[row] then
        listbox:value(row)
        show(rowKeys[row])
    else
        show(nil)
    end
end

local function indexOf(row)
    for index, shown in ipairs(shownRows) do
        if shown == row then
            return index
        end
    end
    return nil
end

local function reselect(row, index) -- the row itself if it still stands, else the one that took its slot
    if rowKeys[row] then
        return pick(row)
    end
    local following = index and shownRows[index] or nil
    pick(following or shownRows[#shownRows])
end

-- ---------------------------------------------------------------- the edits

local function rowOfSelected() -- the picked row as the list spells it now, and where it stands
    local row
    if selected.text then
        row = rowOf(selected.surface, selected.text)
    else
        row = patternRow(document.pattern[selected.pattern])
    end
    return row, indexOf(row)
end

local function settle(row, index) -- after an edit: the rows and the pick
    refresh()
    reselect(row, index)
end

local function writeEntry(surface, source, translation) -- into the document and the file both
    if document.text[surface] == nil then
        document.text[surface] = {}
    end
    document.text[surface][source] = translation
    entriesTable:put{ language = currentLanguage, surface = surface, source = source, translation = translation }
end

local function removeEntry(surface, source)
    document.text[surface][source] = nil
    if next(document.text[surface]) == nil then
        document.text[surface] = nil
    end
    entriesTable:remove(currentLanguage, surface, source)
end

local function writePatterns() -- the language's whole ordered list, after any change to it
    store:transaction(function()
        store:exec("DELETE FROM patterns WHERE language = ?", currentLanguage)
        for position, member in ipairs(document.pattern) do
            patternsTable:put{ language = currentLanguage, position = position,
                               surface = member.surface, match = member.match, text = member.text }
        end
    end)
end

local function save(text)
    if not (selected and currentLanguage) or text == "" then
        return -- nothing to say is nothing to save
    end
    local surface, match = selected.surface, matchEntry:value()
    local row, index = rowOfSelected()
    if match ~= "" then -- a pattern: the one the row shows, or a new one after the last
        local member = { surface = surface, match = match, text = text }
        local patterns = document.pattern
        local patternIndex, before = selected.pattern, nil
        if patternIndex then
            before = patterns[patternIndex]
            patterns[patternIndex] = member
        else
            patterns[#patterns + 1] = member
            patternIndex = #patterns
        end
        if not reload() then -- refused: the document goes back as it was, and the status line says why
            if before then
                patterns[patternIndex] = before
            else
                table.remove(patterns, patternIndex)
            end
            return refresh(refusal)
        end
        writePatterns()
        if selected.text then
            row = rowOf(surface, selected.text)
        else
            row = patternRow(member)
        end
    else
        if selected.text == nil then
            return -- a pattern's row with its match wiped: nothing to write
        end
        writeEntry(surface, selected.text, text)
        reload()
    end
    settle(row, index)
end

local function delete() -- what answers the row goes; a string stays in the list
    if not (selected and currentLanguage) then
        return
    end
    local surface = selected.surface
    local row, index = rowOfSelected()
    if selected.pattern then
        table.remove(document.pattern, selected.pattern)
        writePatterns()
    elseif document.text[surface] and document.text[surface][selected.text] then
        removeEntry(surface, selected.text)
    elseif document.text["*"] and document.text["*"][selected.text] then
        removeEntry("*", selected.text)
    else
        return
    end
    reload()
    settle(row, index)
end

local function ignore()
    if not (selected and selected.text) then
        return
    end
    local surface, text = selected.surface, selected.text
    local row, index = rowOfSelected()
    flag(ignored, surface, text, not flagged(ignored, surface, text))
    reload()
    settle(row, index)
end

local function startPattern() -- start a pattern from the picked string: its English, escaped
    if not (selected and selected.text) then
        return
    end
    matchEntry:value(regex.quote(selected.text))
end

local function export() -- the language's document, as one JSON line on the terminal
    if currentLanguage == nil then
        return
    end
    local exported = { text = document.text }
    if #document.pattern > 0 then
        exported.pattern = document.pattern
    end
    if next(document.text) == nil and exported.pattern == nil then
        return refresh("nothing to export yet")
    end
    hafen.log():write(currentLanguage .. ".json = " .. hafen.json():encode(exported))
    refresh("printed on the terminal as " .. currentLanguage .. ".json")
end

-- ---------------------------------------------------------------- the language

local function syncLanguageDropdown(dropdown) -- the rows and the pick; on the step, since the page's is in a character's tree
    if dropdown and dropdown:exists() then
        dropdown:rows(languageRows())
        dropdown:value(languageOption:value())
    end
end

local function syncLanguageControls()
    syncLanguageDropdown(panelLanguageDropdown)
    syncLanguageDropdown(windowLanguageDropdown)
    refresh()
end

local function applyLanguage(name) -- runs where the option was written; the controls follow on the step
    currentLanguage = (name ~= ENGLISH) and name or nil
    lastMissCount = -1
    local locale = hafen.locale()
    if currentLanguage then
        document = readDocument(currentLanguage)
        local ok, failure = pcall(function() locale:load(catalogue()):install() end)
        if not ok then
            hafen.log():write("the " .. currentLanguage .. " catalogue was refused: " .. tostring(failure))
        end
    else
        document = nil
        locale:release()
    end
    hafen.timer():after(0, syncLanguageControls)
end

local function addLanguage(typed) -- true once the language is in the file and picked
    local name = string.match(typed, "^%s*(.-)%s*$")
    if name == "" then
        return false
    end
    if string.lower(name) == string.lower(ENGLISH) or findLanguage(name) then
        refresh("there is a language called " .. name .. " already")
        return false
    end
    languagesTable:put{ name = name }
    readLanguages()
    languageOption:value(name) -- fires Changed: the new language is installed, empty
    return true
end

local function deleteLanguage(name) -- the language and every translation it holds, in one write
    store:transaction(function()
        store:exec("DELETE FROM entries WHERE language = ?", name)
        store:exec("DELETE FROM patterns WHERE language = ?", name)
        languagesTable:remove(name)
    end)
    readLanguages()
    if name == currentLanguage then
        languageOption:value(ENGLISH) -- fires Changed: the client's own words come back
    else
        hafen.timer():after(0, syncLanguageControls)
    end
end

local function closeConfirm()
    if confirmWindow and confirmWindow:exists() then
        confirmWindow:destroy()
    end
    confirmWindow = nil
end

local function confirmDeleteLanguage() -- a window of its own: the name as its title, Delete and Keep
    if currentLanguage == nil then
        return
    end
    closeConfirm()
    local name = currentLanguage
    local place = window:position()
    confirmWindow = hafen.ui():window():title(name):position(place.x + 40, place.y + 40)
    local column = hafen.ui():column():gap(GAP):parent(confirmWindow):position(0, 0)
    hafen.ui():label():parent(column):text("Delete this language and every translation it holds?")
    local buttons = hafen.ui():row():gap(GAP):parent(column)
    local confirmButton = hafen.ui():button():parent(buttons):size(BUTTON_WIDTH):text("Delete")
    local keepButton = hafen.ui():button():parent(buttons):size(BUTTON_WIDTH):text("Keep")
    confirmWindow:pack()
    confirmButton:on("Pressed", function()
        closeConfirm()
        deleteLanguage(name)
    end)
    keepButton:on("Pressed", closeConfirm)
end

-- ---------------------------------------------------------------- collecting

local function harvest() -- every second: what missed goes into the list
    if not helperOption:value() or currentLanguage == nil then
        return
    end
    local locale = hafen.locale()
    local info = locale:info()
    if not info.installed or info.misses == lastMissCount then
        return
    end
    local added = 0
    for _, miss in ipairs(locale:miss():list()) do
        local surface, text = miss:surface(), miss:text()
        if not flagged(seen, surface, text) and not ownText(surface, text) then
            flag(seen, surface, text, true)
            added = added + 1
        end
    end
    lastMissCount = info.misses
    if info.misses >= RESET_MISSES_AT then -- a fresh round, before the set fills and goes quiet
        locale:install()
        lastMissCount = 0
    end
    if added > 0 then
        refresh()
    end
end

-- ---------------------------------------------------------------- the window

local function build()
    window = hafen.ui():window():title("Translator"):position(80, 80)
    local panel = hafen.ui():column():gap(4):parent(window):position(0, 0):size(WINDOW_WIDTH)

    local topRow = hafen.ui():row():gap(GAP):parent(panel)
    hafen.ui():label():parent(topRow):text("Language")
    windowLanguageDropdown = hafen.ui():dropdown():parent(topRow):size(140)
        :rows(languageRows()):value(languageOption:value())
    hafen.ui():label():parent(topRow):text("Show")
    viewDropdown = hafen.ui():dropdown():parent(topRow):size(100):rows(VIEWS):value("Pending")
    hafen.ui():label():parent(topRow):text("Filter")
    filterEntry = hafen.ui():entry():parent(topRow):size(180)

    local languageRow = hafen.ui():row():gap(GAP):parent(panel)
    hafen.ui():label():parent(languageRow):text("New language")
    local newLanguageEntry = hafen.ui():entry():parent(languageRow):size(140)
    local addButton = hafen.ui():button():parent(languageRow):size(ADD_WIDTH):text("Add")
    deleteLanguageButton = hafen.ui():button():parent(languageRow):size(LANGUAGE_BUTTON_WIDTH)
        :text("Delete language"):enabled(false)
    exportButton = hafen.ui():button():parent(languageRow):size(BUTTON_WIDTH):text("Export"):enabled(false)

    listbox = hafen.ui():listbox():parent(panel):size(WINDOW_WIDTH, 260)
    sourceLabel = hafen.ui():label():parent(panel):text("Pick a row")

    matchRow = hafen.ui():row():gap(GAP):parent(panel)
    hafen.ui():label():parent(matchRow):text("Match")
    matchEntry = hafen.ui():entry():parent(matchRow):size(WINDOW_WIDTH - 40 - BUTTON_WIDTH - 2 * GAP)
    patternButton = hafen.ui():button():parent(matchRow):size(BUTTON_WIDTH):text("Pattern"):enabled(false)

    editRow = hafen.ui():row():gap(GAP):parent(panel)
    translationEntry = hafen.ui():entry():parent(editRow):size(WINDOW_WIDTH - 3 * BUTTON_WIDTH - 3 * GAP)
    local saveButton = hafen.ui():button():parent(editRow):size(BUTTON_WIDTH):text("Save")
    deleteButton = hafen.ui():button():parent(editRow):size(BUTTON_WIDTH):text("Delete"):enabled(false)
    ignoreButton = hafen.ui():button():parent(editRow):size(BUTTON_WIDTH):text("Ignore"):enabled(false)

    statusLabel = hafen.ui():label():parent(panel):text("collecting")
    window:pack()
    window:remember("translator") -- where the user last left it; the client saves it after every drag

    windowLanguageDropdown:on("Changed", function(name) languageOption:value(name) end)
    viewDropdown:on("Changed", function() refresh() end)
    filterEntry:on("Changed", function() refresh() end)
    listbox:on("Changed", function(row) show(rowKeys[row]) end)

    local function addTyped()
        if addLanguage(newLanguageEntry:value()) then
            newLanguageEntry:value("")
        end
    end
    addButton:on("Pressed", addTyped)
    newLanguageEntry:on("Submitted", addTyped)
    deleteLanguageButton:on("Pressed", confirmDeleteLanguage)
    exportButton:on("Pressed", export)

    translationEntry:on("Submitted", save)
    matchEntry:on("Submitted", function() save(translationEntry:value()) end) -- Enter in either field saves the line
    saveButton:on("Pressed", function() save(translationEntry:value()) end)
    patternButton:on("Pressed", startPattern)
    deleteButton:on("Pressed", delete)
    ignoreButton:on("Pressed", ignore)
    window:on("Close", function() -- the X destroys the window: it is built again next time
        closeConfirm()
        window = nil
        settings.windowOpen = false
    end)
    refresh()
end

local function openWindow() -- on the step: a command, a hotkey and the options page each hold a character's tree
    if not helperOption:value() then
        hafen.log():write("the translation helper is off: turn it on in Options > AddOns > Translations")
        return
    end
    if not windowUp() then
        build()
    elseif not window:visible() then
        window:visible(true)
        refresh()
    end
    settings.windowOpen = true
end

local function toggleWindow()
    hafen.timer():after(0, function()
        if windowUp() and window:visible() then
            window:visible(false)
            settings.windowOpen = false
        else
            openWindow()
        end
    end)
end

helperOption:on("Changed", function(on)
    if on then
        if currentLanguage then -- a fresh miss round: the set holds what is drawn from now on
            hafen.locale():install()
            lastMissCount = 0
        end
    else
        hafen.timer():after(0, function()
            closeConfirm()
            if windowUp() then
                window:destroy()
            end
            window = nil
        end)
    end
end)

-- ---------------------------------------------------------------- the options page

options:panel(function(root)
    root:gap(4)
    hafen.ui():label():parent(root):text("Language")
    panelLanguageDropdown = hafen.ui():dropdown():parent(root):size(160)
        :rows(languageRows()):value(languageOption:value())
    panelLanguageDropdown:on("Changed", function(name) languageOption:value(name) end)

    local helperCheck = hafen.ui():check():parent(root)
        :text("Translation helper: collect the strings the language does not name yet"):bind(helperOption)
    local openButton = hafen.ui():button():parent(root):size(OPEN_BUTTON_WIDTH):text("Open the translator")
        :enabled(helperOption:value())
    helperCheck:on("Changed", function(on) openButton:enabled(on) end)
    openButton:on("Pressed", function() hafen.timer():after(0, openWindow) end)
    hafen.ui():label():parent(root):text(":translator opens it too.")
    hafen.ui():label():parent(root):text("A key for it: Options > Game > Keybindings > Translations.")
end)

-- ---------------------------------------------------------------- load

hafen.console():on("translator", toggleWindow)
hafen.client():options():keybindings():on("translator", toggleWindow)
hafen.timer():every(1, harvest)

if languageOption:value() ~= ENGLISH and not languageNameSet[languageOption:value()] then
    languageOption:value(ENGLISH) -- the language it named is not in the file any more
end
languageOption:on("Changed", applyLanguage)
applyLanguage(languageOption:value())
if settings.windowOpen and helperOption:value() then
    build()
end
