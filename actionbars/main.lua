-- Entry point: events and the label timer. The addon has no command and no action-menu entry; everything
-- is managed on Options > AddOns > Actionbars.

local Hotkeys = Actionbars.Hotkeys
local Sync = Actionbars.Sync

-- Hotkeys are declared here as well, so Options > Keybindings lists them before any login.
hafen.event():on("Load", Sync.syncAll)

hafen.event():on("SessionEnteredWorld", Sync.enteredWorld)
for _, eventName in ipairs({"SessionAdded", "SessionRemoved", "SessionSelected"}) do
    hafen.event():on(eventName, Sync.syncAll)
end

hafen.event():on("Disable", Sync.restoreClientBelts)

-- A remap in Options writes the registry and fires nothing: the corner labels are re-read every 2 s.
hafen.timer():every(2, Hotkeys.refreshLabels)
