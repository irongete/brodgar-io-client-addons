-- One hotkey per button, declared as "Actionbar<N> slot <I>": that is the row's caption under
-- Options > Keybindings > Actionbars. Keys start unbound. The assignment lives in the client's registry,
-- so a bar turned off and on again (or a :reload) gets its keys back.

local Layout = Actionbars.Layout
local Slots = Actionbars.Slots

local Hotkeys = {}
Actionbars.Hotkeys = Hotkeys

local keybindings = hafen.client():options():keybindings()
local subscriptions = {} -- [barNumber] = { subscription x12 }
local labels = {} -- [barNumber] = { [slotIndex] = key }: what each button prints in its corner

-- The client's own "Action bar" section (Button 1-12, Go to page 1-12) comes off the keybindings panel while
-- the addon runs, so the rows a user finds for the bars are the addon's. The client's bindings under it keep
-- their keys and keep firing; the panel shows them again when the addon is disabled.
keybindings:section("actionbar"):visible(false)

function Hotkeys.name(barNumber, slotIndex)
    return "Actionbar" .. barNumber .. " slot " .. slotIndex
end

function Hotkeys.bind(barNumber)
    if subscriptions[barNumber] then
        return
    end
    local barSubscriptions = {}
    for slotIndex = 1, Layout.SLOTS_PER_BAR do
        barSubscriptions[slotIndex] = keybindings:on(Hotkeys.name(barNumber, slotIndex), function()
            Slots.press(hafen.session():current(), barNumber, slotIndex) -- the login on screen
        end)
    end
    subscriptions[barNumber] = barSubscriptions
end

function Hotkeys.unbind(barNumber)
    local barSubscriptions = subscriptions[barNumber]
    if not barSubscriptions then
        return
    end
    for _, subscription in ipairs(barSubscriptions) do
        subscription:off()
    end
    subscriptions[barNumber] = nil
end

-- The key bound to each button of the bars declared; nil while unbound. Read on a timer rather than in
-- Draw: twelve registry lookups per bar per frame, for a string that changes only when the user remaps.
function Hotkeys.refreshLabels()
    local refreshed = {}
    for barNumber = 1, Layout.MAX_BARS do
        if subscriptions[barNumber] then
            local barLabels = {}
            for slotIndex = 1, Layout.SLOTS_PER_BAR do
                local binding = keybindings:binding():get(Hotkeys.name(barNumber, slotIndex))
                if binding:exists() then
                    barLabels[slotIndex] = binding:key()
                end
            end
            refreshed[barNumber] = barLabels
        end
    end
    labels = refreshed
end

-- The key to print in the button's corner, or nil.
function Hotkeys.label(barNumber, slotIndex)
    local barLabels = labels[barNumber]
    return barLabels and barLabels[slotIndex]
end
