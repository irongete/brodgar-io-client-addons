-- The translator window: the list, the edit line and the buttons around them. Built when opened, destroyed
-- by its X and built again next time; the client remembers where it stood.

local Config = Translations.Config
local Regex = Translations.Regex
local Store = Translations.Store
local Options = Translations.Options
local Catalogue = Translations.Catalogue
local Rows = Translations.Rows
local Languages = Translations.Languages

local Window = {}
Translations.Window = Window

local window -- nil until it is built and after its X
local listbox, viewDropdown, filterEntry, languageDropdown
local sourceLabel, statusLabel, matchRow, matchEntry, patternButton
local editRow, translationEntry, deleteButton, ignoreButton
local deleteLanguageButton
local confirmWindow -- the "delete this language?" window, while it is up
local selected -- { surface, text } the string picked, or { surface, pattern } a pattern's own row
local shownRows, rowKeys = {}, {} -- the rows on screen, and each row's key

function Window.isUp()
    return window ~= nil and window:exists()
end

-- ---------------------------------------------------------------- the pick

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
        local member = Catalogue.document.pattern[key.pattern]
        sourceLabel:text(Rows.clip(Rows.ofPattern(member), Config.SOURCE_WIDTH))
        matchEntry:value(member.match)
        translationEntry:value(member.text)
        ignoreButton:text("Ignore"):enabled(false)
        deleteButton:enabled(true)
        patternButton:enabled(false)
        return
    end
    local translation = Catalogue.translationOf(key.surface, key.text)
    local patternIndex = (translation == nil) and Catalogue.patternIndexFor(key.surface, key.text) or nil
    key.pattern = patternIndex -- the pattern that answers this string, if one does: Save edits it
    sourceLabel:text(Rows.clip(Rows.ofString(key.surface, key.text), Config.SOURCE_WIDTH))
    if patternIndex then
        local member = Catalogue.document.pattern[patternIndex]
        matchEntry:value(member.match)
        translationEntry:value(member.text)
    else
        matchEntry:value("")
        translationEntry:value(translation or key.text)
    end
    ignoreButton:text(Catalogue.isIgnored(key.surface, key.text) and "Restore" or "Ignore"):enabled(true)
    deleteButton:enabled(translation ~= nil or patternIndex ~= nil)
    patternButton:enabled(true)
end

-- The rows, the enabled state of the edit line and the status line. `note` is what the status line says
-- instead of the counts, this once.
function Window.refresh(note)
    if not Window.isUp() then
        return
    end
    local rows, keys, total, counts = Rows.collect(viewDropdown:value(), filterEntry:value())
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
    local editing = Catalogue.language ~= nil
    editRow:enabled(editing)
    matchRow:enabled(editing)
    deleteLanguageButton:enabled(editing)
    local line = counts.Pending .. " pending, " .. counts.Translated .. " translated, "
        .. counts.Patterns .. " patterns, " .. counts.Ignored .. " ignored"
    if total > Config.MAX_ROWS then
        line = line .. " -- showing " .. Config.MAX_ROWS .. " of " .. total .. ": narrow the filter"
    end
    if note then
        line = counts.Pending .. " pending -- " .. Rows.oneLine(note) -- the shape the counts line has
    end
    statusLabel:text(Rows.clip(line, Config.STATUS_WIDTH))
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
        row = Rows.ofString(selected.surface, selected.text)
    else
        row = Rows.ofPattern(Catalogue.document.pattern[selected.pattern])
    end
    return row, indexOf(row)
end

local function settle(row, index) -- after an edit: the rows and the pick
    Window.refresh()
    reselect(row, index)
end

local function save(text)
    if not (selected and Catalogue.language) or text == "" then
        return
    end
    local surface, match = selected.surface, matchEntry:value()
    local row, index = rowOfSelected()
    if match ~= "" then -- a pattern: the one the row shows, or a new one after the last
        local member = { surface = surface, match = match, text = text }
        if not Catalogue.putPattern(selected.pattern, member) then
            return Window.refresh(Catalogue.refusal) -- nothing written; the status line says why
        end
        if selected.text then
            row = Rows.ofString(surface, selected.text)
        else
            row = Rows.ofPattern(member)
        end
    else
        if selected.text == nil then
            return -- a pattern's row with its match wiped: nothing to write
        end
        Catalogue.putEntry(surface, selected.text, text)
    end
    settle(row, index)
end

local function delete() -- what answers the row goes; a string stays in the list
    if not (selected and Catalogue.language) then
        return
    end
    local row, index = rowOfSelected()
    if selected.pattern then
        Catalogue.removePattern(selected.pattern)
    elseif not Catalogue.removeEntry(selected.surface, selected.text) then
        return
    end
    settle(row, index)
end

local function ignore()
    if not (selected and selected.text) then
        return
    end
    local row, index = rowOfSelected()
    Catalogue.toggleIgnored(selected.surface, selected.text)
    settle(row, index)
end

local function startPattern() -- a pattern from the picked string: its English, escaped
    if not (selected and selected.text) then
        return
    end
    matchEntry:value(Regex.quote(selected.text))
end

-- ---------------------------------------------------------------- the language

function Window.syncLanguage() -- the dropdown's rows and pick follow the file and the option
    if languageDropdown and languageDropdown:exists() then
        languageDropdown:rows(Store.languageRows())
        languageDropdown:value(Options.language:value())
    end
end

function Window.closeConfirm()
    if confirmWindow and confirmWindow:exists() then
        confirmWindow:destroy()
    end
    confirmWindow = nil
end

local function confirmDeleteLanguage() -- a window of its own, titled with the language: Delete and Keep
    if Catalogue.language == nil then
        return
    end
    Window.closeConfirm()
    local name = Catalogue.language
    local place = window:position()
    confirmWindow = hafen.ui():window():title(name):position(place.x + 40, place.y + 40)
    local column = hafen.ui():column():gap(Config.GAP):parent(confirmWindow):position(0, 0)
    hafen.ui():label():parent(column):text("Delete this language and every translation it holds?")
    local buttons = hafen.ui():row():gap(Config.GAP):parent(column)
    local confirmButton = hafen.ui():button():parent(buttons):size(Config.BUTTON_WIDTH):text("Delete")
    local keepButton = hafen.ui():button():parent(buttons):size(Config.BUTTON_WIDTH):text("Keep")
    confirmWindow:pack()
    confirmButton:on("Pressed", function()
        Window.closeConfirm()
        Languages.remove(name)
    end)
    keepButton:on("Pressed", Window.closeConfirm)
end

-- ---------------------------------------------------------------- the window

function Window.build()
    local WIDTH, GAP, BUTTON = Config.WINDOW_WIDTH, Config.GAP, Config.BUTTON_WIDTH
    selected, shownRows, rowKeys = nil, {}, {} -- a new listbox shows nothing yet
    window = hafen.ui():window():title("Translator"):position(80, 80)
    local panel = hafen.ui():column():gap(4):parent(window):position(0, 0):size(WIDTH)

    local topRow = hafen.ui():row():gap(GAP):parent(panel)
    hafen.ui():label():parent(topRow):text("Language")
    languageDropdown = hafen.ui():dropdown():parent(topRow):size(140)
        :rows(Store.languageRows()):value(Options.language:value())
    hafen.ui():label():parent(topRow):text("Show")
    viewDropdown = hafen.ui():dropdown():parent(topRow):size(100):rows(Config.VIEWS):value("Pending")
    hafen.ui():label():parent(topRow):text("Filter")
    filterEntry = hafen.ui():entry():parent(topRow):size(180)

    local languageRow = hafen.ui():row():gap(GAP):parent(panel)
    hafen.ui():label():parent(languageRow):text("New language")
    local newLanguageEntry = hafen.ui():entry():parent(languageRow):size(140)
    local addButton = hafen.ui():button():parent(languageRow):size(Config.ADD_WIDTH):text("Add")
    deleteLanguageButton = hafen.ui():button():parent(languageRow):size(Config.LANGUAGE_BUTTON_WIDTH)
        :text("Delete language"):enabled(false)

    listbox = hafen.ui():listbox():parent(panel):size(WIDTH, Config.LIST_HEIGHT)
    sourceLabel = hafen.ui():label():parent(panel):text("Pick a row")

    matchRow = hafen.ui():row():gap(GAP):parent(panel)
    hafen.ui():label():parent(matchRow):text("Match")
    matchEntry = hafen.ui():entry():parent(matchRow):size(WIDTH - 40 - BUTTON - 2 * GAP)
    patternButton = hafen.ui():button():parent(matchRow):size(BUTTON):text("Pattern"):enabled(false)

    editRow = hafen.ui():row():gap(GAP):parent(panel)
    translationEntry = hafen.ui():entry():parent(editRow):size(WIDTH - 3 * BUTTON - 3 * GAP)
    local saveButton = hafen.ui():button():parent(editRow):size(BUTTON):text("Save")
    deleteButton = hafen.ui():button():parent(editRow):size(BUTTON):text("Delete"):enabled(false)
    ignoreButton = hafen.ui():button():parent(editRow):size(BUTTON):text("Ignore"):enabled(false)

    statusLabel = hafen.ui():label():parent(panel):text("collecting")
    window:pack()
    window:remember("translator") -- where the user last left it; the client saves it after every drag

    languageDropdown:on("Changed", function(name) Options.language:value(name) end)
    viewDropdown:on("Changed", function() Window.refresh() end)
    filterEntry:on("Changed", function() Window.refresh() end)
    listbox:on("Changed", function(row) show(rowKeys[row]) end)

    local function addTyped()
        local added, note = Languages.add(newLanguageEntry:value())
        if added then
            newLanguageEntry:value("")
        elseif note then
            Window.refresh(note)
        end
    end
    addButton:on("Pressed", addTyped)
    newLanguageEntry:on("Submitted", addTyped)
    deleteLanguageButton:on("Pressed", confirmDeleteLanguage)

    translationEntry:on("Submitted", save)
    matchEntry:on("Submitted", function() save(translationEntry:value()) end) -- Enter in either field saves the line
    saveButton:on("Pressed", function() save(translationEntry:value()) end)
    patternButton:on("Pressed", startPattern)
    deleteButton:on("Pressed", delete)
    ignoreButton:on("Pressed", ignore)
    window:on("Close", function() -- the X destroys the window: it is built again next time
        Window.closeConfirm()
        window = nil
        Store.settings.windowOpen = false
    end)
    Window.refresh()
end

-- Runs on the step: the options page's button press runs inside a character's tree. With the helper off
-- there is nothing to collect, so the window stays closed.
function Window.open()
    if not Options.helper:value() or Window.isUp() then
        return
    end
    Window.build()
    Store.settings.windowOpen = true
end

function Window.destroy() -- the helper went off: the window goes, and its confirm window with it
    Window.closeConfirm()
    if Window.isUp() then
        window:destroy()
    end
    window = nil
end
