-- Picking, adding and deleting a language. The `language` option is the one source of truth: writing it
-- fires Changed, which installs the language and brings every control that shows it up to date.

local Config = Translations.Config
local Store = Translations.Store
local Options = Translations.Options
local Catalogue = Translations.Catalogue

local Languages = {}
Translations.Languages = Languages

-- Every control that shows the language, and the list; `note` is for the status line. Runs on the step: the
-- page's dropdown is in a character's tree. window.lua loads after this file: resolved when called.
function Languages.syncControls(note)
    Options.syncLanguage()
    Translations.Window.syncLanguage()
    Translations.Window.refresh(note)
end

-- The option's Changed handler. It runs where the option was written; the controls follow on the step, the
-- status line saying why when the client refused the language's document.
function Languages.apply(name)
    local installed = Catalogue.apply(name)
    hafen.timer():after(0, function()
        Languages.syncControls(not installed and Catalogue.refusal or nil)
    end)
end

-- True once the language is in the file and picked. False when refused, with a note for the status line
-- where there is something to say.
function Languages.add(typed)
    local name = string.match(typed, "^%s*(.-)%s*$")
    if name == "" then
        return false
    end
    if string.lower(name) == string.lower(Config.ENGLISH) or Store.findLanguage(name) then
        return false, "there is a language called " .. name .. " already"
    end
    Store.addLanguage(name)
    Options.language:value(name) -- fires Changed: the new language is installed, empty
    return true
end

function Languages.remove(name) -- the language and every translation it holds
    Store.deleteLanguage(name)
    if name == Catalogue.language then
        Options.language:value(Config.ENGLISH) -- fires Changed: the client's own words come back
    else
        hafen.timer():after(0, Languages.syncControls)
    end
end
