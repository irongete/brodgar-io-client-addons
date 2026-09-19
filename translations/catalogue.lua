-- The installed language: its document, read from the file when the language is picked and written back row
-- by row as it is edited; the lookups the list needs; and the strings collected this session.

local Config = Translations.Config
local Regex = Translations.Regex
local Store = Translations.Store
local Options = Translations.Options

local Catalogue = {}
Translations.Catalogue = Catalogue

Catalogue.language = nil -- the language installed, nil while English is displayed
Catalogue.document = nil -- its document (Store.readDocument), nil while English is displayed
Catalogue.refusal = nil -- what the last :load(doc) said no to, for the status line

-- Not saved: what the client draws is collected again after a reload, and a string put aside is put aside
-- for this session. Shared by every language while it lasts.
Catalogue.seen = {} -- seen[surface][text] = true
local ignored = {} -- the same shape

local lastMissCount = -1 -- the miss count the last harvest read, so an unchanged set is not walked
local compiledPatterns = {} -- match -> the compiled pattern, or false where regex.lua reads none

-- ---------------------------------------------------------------- what is never collected

local ownCaptionSet = {} -- surface -> { caption = true }
for surface, captions in pairs(Config.OWN_CAPTIONS) do
    ownCaptionSet[surface] = {}
    for _, caption in ipairs(captions) do
        ownCaptionSet[surface][caption] = true
    end
end

local function ownLineShape(surface, text) -- a row, the source line or the status line, as Config.OWN_LINE_PATTERNS names them
    return surface == "default" and (string.find(text, "^%[[%a%.%*]+%] ") ~= nil
        or string.find(text, "^%d+ pending") ~= nil)
end

local function ownText(surface, text) -- drawn by this addon's own window or page
    return (ownCaptionSet[surface] ~= nil and ownCaptionSet[surface][text] == true)
        or Store.isLanguage(text)
        or ownLineShape(surface, text)
end

-- ---------------------------------------------------------------- the sets

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

function Catalogue.isIgnored(surface, text)
    return flagged(ignored, surface, text)
end

-- ---------------------------------------------------------------- installing

-- What is installed: the document, plus what is not to be collected.
local function installedDocument()
    local document = Catalogue.document
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
    for _, surface in ipairs(Config.PLAYER_TEXT_SURFACES) do
        pattern[#pattern + 1] = { surface = surface, match = "(?s)(.*)", text = "%1$s" }
    end
    for _, member in ipairs(Config.OWN_LINE_PATTERNS) do
        pattern[#pattern + 1] = member
    end
    return { text = text, pattern = pattern }
end

local function refusalOf(failure) -- the client's reason, without the traceback and the "@main.lua:162 " prefixes a bridge refusal carries
    local refusal = string.gsub(tostring(failure), "\nstack traceback:.*$", "")
    for _ = 1, 3 do
        refusal = string.gsub(refusal, "^@?.-%.lua:%d+:?%s*", "")
    end
    return refusal
end

-- An installed catalogue says the new document at once. False when the client refuses it, with
-- Catalogue.refusal saying why.
function Catalogue.reload()
    if Catalogue.language == nil then
        return true
    end
    local ok, failure = pcall(function() hafen.locale():load(installedDocument()) end)
    if not ok then
        Catalogue.refusal = refusalOf(failure)
    end
    return ok
end

-- Install the language, or give the client its own words back for English. False when the client refuses
-- the language's document, with Catalogue.refusal saying why.
function Catalogue.apply(name)
    Catalogue.language = (name ~= Config.ENGLISH) and name or nil
    lastMissCount = -1
    local locale = hafen.locale()
    if Catalogue.language == nil then
        Catalogue.document = nil
        locale:release()
        return true
    end
    Catalogue.document = Store.readDocument(Catalogue.language)
    local ok, failure = pcall(function() locale:load(installedDocument()):install() end)
    if not ok then
        Catalogue.refusal = refusalOf(failure)
    end
    return ok
end

function Catalogue.startMissRound() -- a fresh miss set: it holds what is drawn from now on
    hafen.locale():install()
    lastMissCount = 0
end

-- ---------------------------------------------------------------- lookups

function Catalogue.translationOf(surface, text) -- the exact entry that answers the string: the surface's, then "*"'s
    local document = Catalogue.document
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

function Catalogue.patternIndexFor(surface, text) -- the first pattern of the language that answers the string, or nil
    local document = Catalogue.document
    if document == nil then
        return nil
    end
    for index, member in ipairs(document.pattern) do
        if member.surface == surface or member.surface == "*" then
            local program = compiledPatterns[member.match]
            if program == nil then
                program = Regex.compile(member.match) or false
                compiledPatterns[member.match] = program
            end
            if program and Regex.matches(program, text) then
                return index
            end
        end
    end
    return nil
end

-- ---------------------------------------------------------------- edits: the document and the file both

function Catalogue.putEntry(surface, source, translation)
    local text = Catalogue.document.text
    if text[surface] == nil then
        text[surface] = {}
    end
    text[surface][source] = translation
    Store.putEntry(Catalogue.language, surface, source, translation)
    Catalogue.reload()
end

function Catalogue.removeEntry(surface, source) -- the surface's entry, else "*"'s; false when there is neither
    local text = Catalogue.document.text
    local owner
    if text[surface] and text[surface][source] then
        owner = surface
    elseif text["*"] and text["*"][source] then
        owner = "*"
    else
        return false
    end
    text[owner][source] = nil
    if next(text[owner]) == nil then
        text[owner] = nil
    end
    Store.removeEntry(Catalogue.language, owner, source)
    Catalogue.reload()
    return true
end

-- Replace pattern `index`, or add one after the last when index is nil. A member the client refuses leaves
-- the document as it was: false, with Catalogue.refusal saying why.
function Catalogue.putPattern(index, member)
    local patterns = Catalogue.document.pattern
    local before = nil
    if index then
        before = patterns[index]
        patterns[index] = member
    else
        patterns[#patterns + 1] = member
        index = #patterns
    end
    if not Catalogue.reload() then
        if before then
            patterns[index] = before
        else
            table.remove(patterns, index)
        end
        return false
    end
    Store.writePatterns(Catalogue.language, patterns)
    return true
end

function Catalogue.removePattern(index)
    local patterns = Catalogue.document.pattern
    table.remove(patterns, index)
    Store.writePatterns(Catalogue.language, patterns)
    Catalogue.reload()
end

function Catalogue.toggleIgnored(surface, text) -- put a string aside, or bring it back
    flag(ignored, surface, text, not flagged(ignored, surface, text))
    Catalogue.reload()
end

-- ---------------------------------------------------------------- collecting

-- What missed since the last call goes into the seen set. Returns how many strings were new.
function Catalogue.harvest()
    if not Options.helper:value() or Catalogue.language == nil then
        return 0
    end
    local locale = hafen.locale()
    local info = locale:info()
    if not info.installed or info.misses == lastMissCount then
        return 0
    end
    local added = 0
    for _, miss in ipairs(locale:miss():list()) do
        local surface, text = miss:surface(), miss:text()
        if not flagged(Catalogue.seen, surface, text) and not ownText(surface, text) then
            flag(Catalogue.seen, surface, text, true)
            added = added + 1
        end
    end
    lastMissCount = info.misses
    if info.misses >= Config.RESET_MISSES_AT then -- a fresh round, before the set fills and goes quiet
        Catalogue.startMissRound()
    end
    return added
end
