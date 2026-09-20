-- Where each bar stands, per character: a var in that character's own scope of the addon's store. A record
-- outlives the bar being turned off, so it comes back where it was. Orientation is an option.

local Layout = Actionbars.Layout

local Positions = {}
Actionbars.Positions = Positions

-- Before 1.0.3 the places were one list for the whole client, in the addon's own scope. It is read for two
-- things: `vert`, which the bar's option defaults to on a client that never stored a value for it, and the
-- place itself, which seeds a character's own record the first time that character shows the bar.
local legacy = hafen.store():var("bars")
legacy.list = legacy.list or {} -- { {barNumber=, x=, y=}, ... }

local legacyUpright = {} -- [barNumber] = true | false, for every bar that had a record at load
for _, record in ipairs(legacy.list) do
    if record.n ~= nil then
        record.barNumber = record.n
        record.n = nil
    end
    legacyUpright[record.barNumber] = record.vert == true
    record.vert = nil
end

-- nil for a bar with no record at load, else whether it stood upright.
function Positions.legacyUpright(barNumber)
    return legacyUpright[barNumber]
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
    if not (session:exists() and session:character()) then
        return nil
    end
    local ok, saved = pcall(function()
        return session:store():var("bars")
    end)
    if not ok then
        return nil
    end
    saved.list = saved.list or {} -- { {barNumber=, x=, y=}, ... }
    return saved.list
end

function Positions.find(session, barNumber)
    local list = listFor(session)
    return list and findIn(list, barNumber)
end

function Positions.save(session)
    if session:exists() and session:character() then
        session:store():flush()
    end
end

-- Centre of the screen for a box: where a bar first appears, and what Reset gives a lone bar.
function Positions.centre(boxWidth, boxHeight, screenWidth, screenHeight)
    local x = math.max(0, math.floor((screenWidth - boxWidth) / 2))
    local y = math.max(0, math.floor((screenHeight - boxHeight) / 2))
    return x, y
end

-- That character's record, created on first use: where the client-wide list of earlier versions had the
-- bar, else the centre of the screen. A HUD with no size yet (nil or 0) gives the default place instead.
-- nil for a session that has no character yet.
function Positions.recordFor(session, barNumber, boxWidth, boxHeight, screenWidth, screenHeight)
    local list = listFor(session)
    if not list then
        return nil
    end
    local record = findIn(list, barNumber)
    if record then
        return record
    end

    local x, y = Layout.DEFAULT_X, Layout.DEFAULT_Y
    local inherited = findIn(legacy.list, barNumber)
    if inherited then
        x, y = inherited.x, inherited.y
    elseif screenWidth and screenWidth > 0 and screenHeight and screenHeight > 0 then
        x, y = Positions.centre(boxWidth, boxHeight, screenWidth, screenHeight)
    end

    record = {barNumber = barNumber, x = x, y = y}
    list[#list + 1] = record
    table.sort(list, function(first, second)
        return first.barNumber < second.barNumber
    end)
    Positions.save(session)
    return record
end
