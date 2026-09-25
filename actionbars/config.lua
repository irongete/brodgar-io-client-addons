-- One character's bars: which are on, which way each stands and how many buttons it shows. All of it is a
-- var in that character's own scope of the addon's store, so every character has their own, and one nobody
-- has played with starts with Actionbar1 alone, flat, centred on the bottom edge of the screen. A record
-- outlives the bar being turned off, so it comes back as it was. Where a bar stands is the client's to keep
-- (bars.lua); a place saved here is an earlier version's.

local Layout = Actionbars.Layout

local Config = {}
Actionbars.Config = Config

Config.OFF = "off"
Config.FLAT = "flat"
Config.UPRIGHT = "upright"

-- What a bar is before its character has set anything: the main bar flat, every other off, all twelve
-- buttons. The place is decided when the bar is first built, against the HUD it stands on.
local function defaultMode(barNumber)
    if barNumber == Layout.MAIN_BAR then
        return Config.FLAT
    end
    return Config.OFF
end

local function findIn(list, barNumber)
    for _, record in ipairs(list) do
        if record.barNumber == barNumber then
            return record
        end
    end
    return nil
end

-- That character's saved list, or nil for a session that has no character yet (connecting, or on the
-- character list): its scope arrives with SessionEnteredWorld, and there is no HUD to put a bar on before.
local function listFor(session)
    if not (session and session:exists() and session:character()) then
        return nil
    end
    local ok, saved = pcall(function()
        return session:store():var("bars")
    end)
    if not ok then
        return nil
    end
    saved.list = saved.list or {} -- { {barNumber=, mode=, buttons=, x=, y=}, ... }
    return saved.list
end

-- Whether the session has a character whose settings can be read and written.
function Config.ready(session)
    return listFor(session) ~= nil
end

-- That character's record for the bar, or nil while there is none: the bar has never been built, set or
-- moved for this character, so it is at its default.
function Config.find(session, barNumber)
    local list = listFor(session)
    return list and findIn(list, barNumber)
end

-- The record, created at the default when there is none. nil for a session with no character.
local function recordFor(session, barNumber)
    local list = listFor(session)
    if not list then
        return nil
    end
    local record = findIn(list, barNumber)
    if record then
        return record
    end
    record = {barNumber = barNumber, mode = defaultMode(barNumber), buttons = Layout.SLOTS_PER_BAR}
    list[#list + 1] = record
    table.sort(list, function(first, second)
        return first.barNumber < second.barNumber
    end)
    return record
end

function Config.save(session)
    if session and session:exists() and session:character() then
        session:store():flush()
    end
end

-- ---------------------------------------------------------------- mode and button count

function Config.mode(session, barNumber)
    local record = Config.find(session, barNumber)
    return (record and record.mode) or defaultMode(barNumber)
end

function Config.isOn(session, barNumber)
    return Config.mode(session, barNumber) ~= Config.OFF
end

function Config.isUpright(session, barNumber)
    return Config.mode(session, barNumber) == Config.UPRIGHT
end

-- How many of the bar's twelve slots it shows, from the first.
function Config.buttonCount(session, barNumber)
    local record = Config.find(session, barNumber)
    return (record and record.buttons) or Layout.SLOTS_PER_BAR
end

function Config.countOn(session)
    local count = 0
    for barNumber = 1, Layout.MAX_BARS do
        if Config.isOn(session, barNumber) then
            count = count + 1
        end
    end
    return count
end

-- Write and save; false for a session with no character to write for.
function Config.setMode(session, barNumber, mode)
    local record = recordFor(session, barNumber)
    if not record then
        return false
    end
    record.mode = mode
    Config.save(session)
    return true
end

function Config.setButtonCount(session, barNumber, count)
    local record = recordFor(session, barNumber)
    if not record then
        return false
    end
    record.buttons = count
    Config.save(session)
    return true
end

-- ---------------------------------------------------------------- the place

-- Centre of the screen for a box: where a bar other than Actionbar1 first appears.
function Config.centre(boxWidth, boxHeight, screenWidth, screenHeight)
    local x = math.max(0, math.floor((screenWidth - boxWidth) / 2))
    local y = math.max(0, math.floor((screenHeight - boxHeight) / 2))
    return x, y
end

-- The place 1.0.5 and earlier kept for this character's bar, in pixels: where it first appeared, a drag's
-- or Reset's. nil when there is none. It still starts the bar until a place the client keeps outranks it or
-- Reset forgets it.
function Config.oldPlace(session, barNumber)
    local record = Config.find(session, barNumber)
    if record and record.x and record.y then
        return record.x, record.y
    end
    return nil
end

function Config.forgetOldPlace(session, barNumber)
    local record = Config.find(session, barNumber)
    if record then
        record.x, record.y = nil, nil
    end
end
