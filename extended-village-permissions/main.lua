-- Extended village permissions: a polity's groups run 0..254 but the client only draws eight colour squares.
-- Every colour row that can use the whole range (Village and Realm tabs, and the member panel) gets a
-- dropdown with all 255 groups. The dropdown mirrors the row (`row:value()`) and drives it (`row:value(n)`),
-- so the message to the server is the window's own. Member and kin rows also get the group number painted
-- at their right edge, since every group above the eighth is drawn in the same colour.

local PICKER_WIDTH = 64 -- design px; the colour row is 160 wide and the panel 263, so it fits under or beside
local PICKER_GAP = 2 -- design px between the colour row and the picker
local SYNC_SECONDS = 0.25 -- how often the pickers re-read what their rows show

-- Panels whose colour row gets no picker. Landwindow: a claim holds eight permission rows, so a group
-- above the eighth is accepted by the server and then dropped. The Kin tab's own row is also skipped, but
-- it needs no entry here: the kin window is not walkable from inside, so `colourRow:parent()` is nil.
local NO_PICKER = {Landwindow = true}

-- Dropdown rows are strings, and "Changed" hands the chosen string back.
local GROUP_ROWS = {}
for groupNumber = 0, 254 do
    GROUP_ROWS[groupNumber + 1] = tostring(groupNumber)
end

local groupRowWatchByUser = {} -- [user] = the "@GroupSelector" Added subscription on that session
local memberRowWatchByUser = {} -- [user] = the "@ItemWidget" Added subscription on that session
local pickers = {} -- {row =, picker =, seen = the group the row last reported}

local function log(line)
    hafen.log():write("extended-village-permissions: " .. line)
end

-- ---------------------------------------------------------------- the picker

-- Under the colour row if nothing the server placed there is in the way, otherwise beside it.
local function placeFor(colourRow, pickerHeight)
    local rowPosition, rowSize = colourRow:position(), colourRow:size()
    local underY = rowPosition.y + rowSize.h + PICKER_GAP
    local firstObstacleY = nil
    for _, sibling in ipairs(colourRow:parent():children():list()) do
        local siblingPosition, siblingSize = sibling:position(), sibling:size()
        local below = siblingPosition.y >= rowPosition.y + rowSize.h
        local overlapsX = siblingPosition.x < rowPosition.x + PICKER_WIDTH
            and siblingPosition.x + siblingSize.w > rowPosition.x
        if below and overlapsX and (firstObstacleY == nil or siblingPosition.y < firstObstacleY) then
            firstObstacleY = siblingPosition.y
        end
    end
    if firstObstacleY == nil or firstObstacleY - underY >= pickerHeight then
        return rowPosition.x, underY
    end
    return rowPosition.x + rowSize.w + PICKER_GAP, rowPosition.y
end

local function addPicker(colourRow)
    local panel = colourRow:parent()
    if panel == nil or NO_PICKER[panel:type()] then
        return
    end
    local pickerName = "group" .. tostring(colourRow:position().y)
    if panel:matchAll("[name=extended-village-permissions/" .. pickerName .. "]")[1] then
        return -- already has one
    end

    local picker = hafen.ui():dropdown():parent(panel):name(pickerName):size(PICKER_WIDTH):rows(GROUP_ROWS)
        :tooltip("the group this row is in, and where to put it -- 0-254, the range the server takes;"
            .. " the eight colours only reach 0-7")
    picker:position(placeFor(colourRow, picker:size().h))
    picker:on("Changed", function(chosenRow)
        local group = tonumber(chosenRow)
        -- The drive runs the panel's own hook; a panel that cannot hold the group throws, and the row stays.
        local driven, failure = pcall(function()
            colourRow:value(group)
        end)
        if not driven then
            log(tostring(failure))
        end
    end)
    pickers[#pickers + 1] = {row = colourRow, picker = picker}
end

-- The group changes under the addon (the tab switches group, the server rebuilds the member row), so the
-- pickers re-read their rows instead of remembering.
hafen.timer():every(SYNC_SECONDS, function()
    for index = #pickers, 1, -1 do
        local entry = pickers[index]
        if not (entry.row:exists() and entry.picker:exists()) then
            table.remove(pickers, index)
        else
            local group = entry.row:value()
            if group ~= entry.seen then
                entry.seen = group
                if group then
                    entry.picker:value(tostring(group))
                end
            end
        end
    end
end)

local function watchGroupRows(session)
    local previous = groupRowWatchByUser[session:user()]
    if previous then
        previous:off()
    end
    groupRowWatchByUser[session:user()] = session:ui():on("@GroupSelector", "Added", addPicker)
    -- Rows already open (a reload, or a window remembered open) get no "Added".
    for _, colourRow in ipairs(session:ui():matchAll("@GroupSelector")) do
        addPicker(colourRow)
    end
end

-- ---------------------------------------------------------------- the number on a member's row

-- Read inside the painter, not captured: the server re-adds a member when their group changes, and the
-- row is rebuilt as the list scrolls.
local function numberRow(memberRow)
    if memberRow:group() == nil then
        return -- only a polity member's row has a group
    end
    memberRow:overlay():add("group"):draw(function(graphics, width, height)
        local group = memberRow:group()
        if group == nil then
            return
        end
        graphics:color(210, 210, 210)
        graphics:atext(tostring(group), width - 2, height / 2, 1.0, 0.5)
    end)
end

local function watchMemberRows(session)
    local previous = memberRowWatchByUser[session:user()]
    if previous then
        previous:off()
    end
    memberRowWatchByUser[session:user()] = session:ui():on("@ItemWidget", "Added", numberRow)
    for _, memberRow in ipairs(session:ui():matchAll("@ItemWidget")) do
        numberRow(memberRow)
    end
end

hafen.event():on("SessionEnteredWorld", watchGroupRows)
hafen.event():on("SessionEnteredWorld", watchMemberRows)
hafen.event():on("SessionRemoved", function(session)
    groupRowWatchByUser[session:user()] = nil
    memberRowWatchByUser[session:user()] = nil
end)

-- ---------------------------------------------------------------- :evp

-- Lists every colour row of the current character, its group, and whether it got a picker.
hafen.console():on("evp", function()
    local session = hafen.session():current()
    if not session then
        log("no character on screen")
        return
    end
    local colourRows = session:ui():matchAll("@GroupSelector")
    log(#colourRows .. " colour rows in this character's tree")
    for index, colourRow in ipairs(colourRows) do
        local rowPosition, panel = colourRow:position(), colourRow:parent()
        local pickerState
        if panel == nil then
            pickerState = "none (the kin window is not walkable from inside)"
        elseif NO_PICKER[panel:type()] then
            pickerState = "none (the eight are the whole space here)"
        else
            pickerState = tostring(panel:matchAll("[name^=extended-village-permissions/]")[1] ~= nil)
        end
        log("  row " .. index .. ": panel=" .. (panel and panel:type() or "unreachable")
            .. " group=" .. tostring(colourRow:value()) .. " at " .. rowPosition.x .. "," .. rowPosition.y
            .. " picker=" .. pickerState)
    end
end)
