-- The belt slot behind a bar's button, and pressing it.

local Layout = Actionbars.Layout

local Slots = {}
Actionbars.Slots = Slots

local mouse = hafen.ui():mouse()

-- The Slot behind button `slotIndex`, or nil once the session is gone. MAIN_BAR shows the client's current
-- page; every other bar is nailed to page `barNumber`. Runs per cell per frame: one actionbar() serves
-- both the page and the slot.
function Slots.get(session, barNumber, slotIndex)
    if not (session and session:exists()) then
        return nil
    end
    local actionbar = session:actionbar()
    local page = barNumber
    if barNumber == Layout.MAIN_BAR then
        page = actionbar:page()
    end
    return actionbar:get(((page - 1) * Layout.SLOTS_PER_BAR) + slotIndex)
end

-- The bitfield slot:use takes (Shift 1, Ctrl 2, Alt 4), from the keys held now: a Shift-click or a hotkey
-- with Shift held means what it does on the client's own belt.
function Slots.modifiers()
    local bits = 0
    if mouse:shift() then
        bits = bits + 1
    end
    if mouse:ctrl() then
        bits = bits + 2
    end
    if mouse:alt() then
        bits = bits + 4
    end
    return bits
end

-- Fire a loaded slot. use() raises on an empty one, so callers skip those; a refusal from the permission
-- gate or the server is logged.
function Slots.use(slot)
    local ok, failure = pcall(function()
        slot:use(Slots.modifiers())
    end)
    if not ok then
        hafen.log():write(failure)
    end
end

function Slots.press(session, barNumber, slotIndex)
    local slot = Slots.get(session, barNumber, slotIndex)
    if slot and not slot:empty() then
        Slots.use(slot)
    end
end
