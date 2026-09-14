-- Auto FlowerMenu: when a flowermenu opens, picks the first petal on the user's list that the menu offers.
-- The list is edited in Options > AddOns > Auto FlowerMenu; the order is the priority.

local ENTRY_WIDTH = 160
local ADD_WIDTH = 50
local MOVE_WIDTH = 50
local REMOVE_WIDTH = 24 -- a Button narrower than 24 clips its art

-- ---------------------------------------------------------------- the list
--
-- `settings` is a store var: a live table saved in the addon's own file, shared by every account and
-- character on this client. Writing into it is saving; flush() writes it to disk now instead of on the timer.
local settings = hafen.store():var("settings")
if settings.labels == nil then
    settings.labels = {}
end

local function save()
    hafen.store():flush()
end

-- Captions match whole and case-insensitively, the same way flowermenu():select(label) does.
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
    caption = caption:match("^%s*(.-)%s*$")
    if caption == "" or findLabel(caption) then
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

local function swapLabels(firstIndex, secondIndex)
    local labels = settings.labels
    if labels[firstIndex] == nil or labels[secondIndex] == nil then
        return
    end
    labels[firstIndex], labels[secondIndex] = labels[secondIndex], labels[firstIndex]
    save()
end

-- ---------------------------------------------------------------- picking

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
    -- Hidden before its first frame: a menu that gets picked is never painted.
    session:flowermenu():visible(false):select(chosen)
end)

-- ---------------------------------------------------------------- the options page
--
-- The client rebuilds the page on every visit, so the rows are built from `settings.labels` each time.
-- Button handlers defer with timer():after(0) so the rows are rebuilt outside the press that triggered it.
local options = hafen.client():options():addon()

local refreshRows -- defined below; a row's buttons call it

local function buildRow(listColumn, index, label)
    local row = hafen.ui():row():gap(4):parent(listColumn)

    local upButton = hafen.ui():button():parent(row):size(MOVE_WIDTH):text("Up")
        :tooltip("pick " .. label .. " before the one above it")
    upButton:enabled(index > 1)
    upButton:on("Pressed", function()
        hafen.timer():after(0, function()
            swapLabels(index, index - 1)
            refreshRows(listColumn)
        end)
    end)

    local downButton = hafen.ui():button():parent(row):size(MOVE_WIDTH):text("Down")
        :tooltip("pick " .. label .. " after the one below it")
    downButton:enabled(index < #settings.labels)
    downButton:on("Pressed", function()
        hafen.timer():after(0, function()
            swapLabels(index, index + 1)
            refreshRows(listColumn)
        end)
    end)

    local removeButton = hafen.ui():button():parent(row):size(REMOVE_WIDTH):text("X")
        :tooltip("take " .. label .. " off the list")
    removeButton:on("Pressed", function()
        hafen.timer():after(0, function()
            removeLabel(index)
            refreshRows(listColumn)
        end)
    end)

    -- A row aligns children to the top; a top margin centres the label against the buttons.
    local nameLabel = hafen.ui():label():parent(row):text(label)
    local labelOffset = math.floor((removeButton:size().h - nameLabel:size().h) / 2)
    nameLabel:rule():margin(0, labelOffset, 0, 0)
end

refreshRows = function(listColumn)
    if not listColumn:exists() then
        return -- the page was closed before the deferred step ran
    end

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
    local captionEntry = hafen.ui():entry():parent(addRow):size(ENTRY_WIDTH)
        :tooltip("a petal's caption, as the menu shows it: Pick, Chop, Harvest...")
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
