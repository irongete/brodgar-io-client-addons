-- Entry point: the three widgets, and the events that keep the client's own meters in step with them.

local Config = HUD.Config
local Meters = HUD.Meters
local Bars = HUD.Bars

Bars.build()

Config.enabledOption:on("Changed", Meters.reconcileSoon)

hafen.event():on("SessionEnteredWorld", function(session)
  Meters.forget(session)
  Meters.restore(session)                    -- the widgets held belonged to the tree the switch replaced
  Meters.reconcileSoon()
end)

-- A meter appearing is the one moment there is something new to hide.
hafen.event():on("MeterAdded", Meters.reconcileSoon)

hafen.event():on("SessionRemoved", Meters.drop)

-- A meter has no toggle of its own, so nothing else would bring back a hidden one. Disable fires before
-- the teardown.
hafen.event():on("Disable", function()
  Bars.releaseDrag()
  Meters.restoreAll()
end)

-- An addon loaded while characters are already up receives no event for them.
Meters.reconcileSoon()
