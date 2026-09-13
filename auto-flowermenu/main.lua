-- Auto FlowerMenu -- whenever a radial menu opens, picks the first petal on your list that the ring
-- offers, the instant the ring opens. The list is yours: add any petal caption in
-- Options > AddOns > Auto FlowerMenu and order it by priority -- the entry nearest the top that the ring
-- offers is the one picked.
local ENTRY_WIDTH = 160 -- the field a new caption is typed in
local ADD_WIDTH = 50 -- the Add button beside it
local MOVE_WIDTH = 50 -- the Up and Down buttons of a row
local REMOVE_WIDTH = 24 -- the X of a row: a Button's own art is 24 wide, and narrower clips it

-- ---------------------------------------------------------------- the list
--
-- The list is saved for the ACCOUNT, so every character picks from the same one. An account table is
-- filled before this file runs, and it is the table itself: writing into it is saving, and flush() is
-- what puts it on disk right away rather than on the timer. It starts empty: every caption on it is
-- one the user added.
local settings = hafen.store():get("settings")
if settings.labels == nil then
    settings.labels = {}
end

local function save()
    hafen.store():flush()
end

-- A caption is matched whole and without regard to case, exactly as s:flowermenu():select(label) does.
local function sameCaption(first, second)
    return first:lower() == second:lower()
end

local function findLabel(caption)
    for index, label in ipairs(settings.labels) do
        if sameCaption(label, caption) then
            return index
        end
    end
    return nil
end

local function addLabel(caption)
    caption = caption:match("^%s*(.-)%s*$") -- trimmed: the ring never paints the spaces
    if caption == "" then
        return false
    end
    if findLabel(caption) then
        return false
    end
    table.insert(settings.labels, caption)
    save()
    return true
end

local function removeLabel(index)
    table.remove(settings.labels, index)
    save()
end

-- Swapping two neighbours is the whole of reordering: Up swaps with the one above, Down with the one below.
local function swapLabels(firstIndex, secondIndex)
    local labels = settings.labels
    if labels[firstIndex] == nil or labels[secondIndex] == nil then
        return
    end
    labels[firstIndex], labels[secondIndex] = labels[secondIndex], labels[firstIndex]
    save()
end

-- ---------------------------------------------------------------- picking
--
-- The list is walked in order, and the first entry the ring offers wins: that is what makes the order
-- a priority.
local function labelToPick(petals)
    for _, wanted in ipairs(settings.labels) do
        for _, petal in ipairs(petals) do
            if sameCaption(petal:label() or "", wanted) then
                return wanted
            end
        end
    end
    return nil
end

hafen.event():on("FlowerMenuAdded", function(petals, session)
    local chosen = labelToPick(petals)
    if chosen == nil then
        return
    end
    -- Decided before the ring's first frame, so a ring that was always going to be picked is never painted.
    session:flowermenu():visible(false):select(chosen)
end)

-- ---------------------------------------------------------------- the page
--
-- Options > AddOns > Auto FlowerMenu. The client hands over a column and rebuilds it on every visit, so
-- nothing built here is kept: the list lives in `settings`, and the rows are built from it each time.
--
-- A button's Pressed handler holds the Options window's tree, and a control is born in the addon layer
-- before :parent() moves it in -- a second tree. So a press changes the list and lets the next step
-- rebuild the rows, holding nothing.
local options = hafen.client():options():addon()

local refreshRows -- forward: a row's buttons rebuild the rows they stand in

local function buildRow(listColumn, index, label)
    local row = hafen.ui():row():gap(4):parent(listColumn)

    local upButton = hafen.ui():button():parent(row):size(MOVE_WIDTH):text("Up"):tooltip("pick " .. label ..
                                                                                             " before the one above it")
    upButton:enabled(index > 1)
    upButton:on("Pressed", function()
        hafen.timer():after(0, function()
            swapLabels(index, index - 1)
            refreshRows(listColumn)
        end)
    end)

    local downButton = hafen.ui():button():parent(row):size(MOVE_WIDTH):text("Down"):tooltip("pick " .. label ..
                                                                                                 " after the one below it")
    downButton:enabled(index < #settings.labels)
    downButton:on("Pressed", function()
        hafen.timer():after(0, function()
            swapLabels(index, index + 1)
            refreshRows(listColumn)
        end)
    end)

    local removeButton = hafen.ui():button():parent(row):size(REMOVE_WIDTH):text("X"):tooltip("take " .. label ..
                                                                                                  " off the list")
    removeButton:on("Pressed", function()
        hafen.timer():after(0, function()
            removeLabel(index)
            refreshRows(listColumn)
        end)
    end)

    -- A row keeps every child at its top, and a label is shorter than a button: a top margin centres it.
    local nameLabel = hafen.ui():label():parent(row):text(label)
    local labelOffset = math.floor((removeButton:size().h - nameLabel:size().h) / 2)
    nameLabel:rule():margin(0, labelOffset, 0, 0)
end

refreshRows = function(listColumn)
    if not listColumn:exists() then
        return
    end -- the page was left before the step came round

    for _, child in ipairs(listColumn:children():list()) do
        child:destroy()
    end

    if #settings.labels == 0 then
        hafen.ui():label():parent(listColumn):text("Nothing on the list yet.")
        return
    end

    for index, label in ipairs(settings.labels) do
        buildRow(listColumn, index, label)
    end
end

options:panel(function(root)
    root:gap(4)
    hafen.ui():label():parent(root):text("Petals picked automatically, in order of priority:")
    hafen.ui():label():parent(root):text("The first one on the list that the flowermenu offers is the one picked.")

    local addRow = hafen.ui():row():gap(4):parent(root)
    local captionEntry = hafen.ui():entry():parent(addRow):size(ENTRY_WIDTH):tooltip(
        "a petal's caption, as the ring paints it: Pick, Chop, Harvest...")
    local addButton = hafen.ui():button():parent(addRow):size(ADD_WIDTH):text("Add")

    local listColumn = hafen.ui():column():gap(2):parent(root)

    local function addTyped()
        local caption = captionEntry:value()
        hafen.timer():after(0, function()
            if not addLabel(caption) then
                return
            end
            if captionEntry:exists() then
                captionEntry:value("")
            end
            refreshRows(listColumn)
        end)
    end
    addButton:on("Pressed", addTyped)
    captionEntry:on("Submitted", addTyped)

    refreshRows(listColumn)
end)
