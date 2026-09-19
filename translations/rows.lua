-- The rows of the list: "[surface] text" for a string, "[surface] /match/" for a pattern's own row, and
-- which of them the view and the filter keep.

local Config = Translations.Config
local Catalogue = Translations.Catalogue

local Rows = {}
Translations.Rows = Rows

function Rows.oneLine(text)
    return (string.gsub(text, "[\r\n]+", " "))
end

function Rows.clip(text, limit) -- at most limit bytes, never cutting a UTF-8 character in two
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

function Rows.ofString(surface, text)
    return "[" .. surface .. "] " .. Rows.oneLine(text)
end

function Rows.ofPattern(member) -- its match between slashes
    return "[" .. member.surface .. "] /" .. Rows.oneLine(member.match) .. "/"
end

local function knownStrings() -- the strings seen this session, and every string the language names, seen or not
    local all = {}
    for surface, texts in pairs(Catalogue.seen) do
        all[surface] = {}
        for text in pairs(texts) do
            all[surface][text] = true
        end
    end
    local document = Catalogue.document
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

-- The rows `view` (one of Config.VIEWS) and `filter` (a fragment of the row) keep, sorted by surface then
-- text, the patterns first in the order they answer in. Returns the rows (the first MAX_ROWS), each row's key
-- ({ surface, text } for a string, { surface, pattern = index } for a pattern's own row), the total before
-- the cap, and the counts per state.
function Rows.collect(view, filter)
    view = view or "Pending"
    local needle = string.lower(filter or "")
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
            if total <= Config.MAX_ROWS then
                rows[#rows + 1] = row
                keys[row] = key
            end
        end
    end
    local document = Catalogue.document
    if document then
        counts.Patterns = #document.pattern
        if view == "All" or view == "Translated" then
            for index, member in ipairs(document.pattern) do
                keep(Rows.ofPattern(member), { surface = member.surface, pattern = index })
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
            if Catalogue.isIgnored(surface, text) then
                state = "Ignored"
            elseif Catalogue.translationOf(surface, text) or Catalogue.patternIndexFor(surface, text) then
                state = "Translated"
            else
                state = "Pending"
            end
            counts[state] = counts[state] + 1
            if view == "All" or view == state then
                keep(Rows.ofString(surface, text), { surface = surface, text = text })
            end
        end
    end
    return rows, keys, total, counts
end
