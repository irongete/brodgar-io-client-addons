-- Entry point: events, the console command, the action-menu entry and the label timer.

local Layout = Actionbars.Layout
local Options = Actionbars.Options
local Hotkeys = Actionbars.Hotkeys
local Sync = Actionbars.Sync

local icon -- icon.png, loaded once

local function tell()
    local bars = {}
    for barNumber = 1, Layout.MAX_BARS do
        if Options.isOn(barNumber) then
            bars[#bars + 1] = "Actionbar" .. barNumber .. " " .. Options.mode(barNumber)
        end
    end
    hafen.log():write("Actionbars: " .. table.concat(bars, ", "))
    hafen.log():write("Actionbars: add, remove and rotate them in Options > AddOns > Actionbars")
end

-- Hotkeys are declared here as well, so Options > Keybindings lists them before any login.
hafen.event():on("Load", function()
    icon = hafen.asset():get("icon.png")
    Sync.syncAll()
end)

-- One entry per character in the action menu; a Paginae like any other, so it can be dragged onto a bar.
-- Its id "panel" is kept: a belt slot holding the entry holds it by that id, and a rename would orphan it.
hafen.event():on("SessionEnteredWorld", function(session)
    local ok, failure = pcall(function()
        local entry = session:menugrid():add("panel"):name("Actionbars")
            :tooltip("what is on, and where the bars are managed")
        if icon then
            entry:icon(icon)
        end
        entry:on("Pressed", tell)
    end)
    if not ok then
        hafen.log():write(failure)
    end
    Sync.syncAll()
end)

for _, eventName in ipairs({"SessionAdded", "SessionRemoved", "SessionSelected"}) do
    hafen.event():on(eventName, Sync.syncAll)
end

hafen.event():on("Disable", Sync.restoreClientBelts)

hafen.console():on("actionbars", tell) -- the one door that answers before a character is in the world

-- A remap in Options writes the registry and fires nothing: the corner labels are re-read every 2 s.
hafen.timer():every(2, Hotkeys.refreshLabels)
