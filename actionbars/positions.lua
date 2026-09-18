-- Where each bar stands: the addon's own store var, shared by every account and character on this client.
-- A record outlives the bar being turned off, so it comes back where it was. Orientation is an option.

local Layout = Actionbars.Layout

local Positions = {}
Actionbars.Positions = Positions

local saved = hafen.store():var("bars")
saved.list = saved.list or {} -- { {barNumber=, x=, y=}, ... }

-- Records written before the options existed carry `n` and `vert`. `n` is renamed. `vert` is what the bar's
-- option defaults to on a client that has never stored a value for it; read once here, then dropped.
local legacyUpright = {} -- [barNumber] = true | false, for every bar that had a record at load
for _, record in ipairs(saved.list) do
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

function Positions.find(barNumber)
    for _, record in ipairs(saved.list) do
        if record.barNumber == barNumber then
            return record
        end
    end
    return nil
end

function Positions.save()
    hafen.store():flush()
end

-- Centre of the screen for a box: where a bar first appears, and what Reset gives a lone bar.
function Positions.centre(boxWidth, boxHeight, screenWidth, screenHeight)
    local x = math.max(0, math.floor((screenWidth - boxWidth) / 2))
    local y = math.max(0, math.floor((screenHeight - boxHeight) / 2))
    return x, y
end

-- The record, created on first use at the centre of the screen. A HUD with no size yet (nil or 0) gives the
-- default place instead.
function Positions.recordFor(barNumber, boxWidth, boxHeight, screenWidth, screenHeight)
    local record = Positions.find(barNumber)
    if record then
        return record
    end

    local x, y = Layout.DEFAULT_X, Layout.DEFAULT_Y
    if screenWidth and screenWidth > 0 and screenHeight and screenHeight > 0 then
        x, y = Positions.centre(boxWidth, boxHeight, screenWidth, screenHeight)
    end

    record = {barNumber = barNumber, x = x, y = y}
    saved.list[#saved.list + 1] = record
    table.sort(saved.list, function(first, second)
        return first.barNumber < second.barNumber
    end)
    Positions.save()
    return record
end
