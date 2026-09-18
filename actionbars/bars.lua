-- The widgets of one bar, one copy per login. Bars hang on the character's HUD (@GameUI), not in the addon
-- layer: the action menu ends its drag on the session's widget tree, and a bar in the addon layer would
-- never receive the Drop. A copy is built per login from SessionEnteredWorld and dies with its tree.

local Layout = Actionbars.Layout
local Positions = Actionbars.Positions
local Options = Actionbars.Options
local Slots = Actionbars.Slots
local Hotkeys = Actionbars.Hotkeys

local Bars = {}
Actionbars.Bars = Bars

local barsBySession = {} -- [session] = { [barNumber] = bar widget }

local LABEL_STYLE = {color = Layout.LABEL_COLOR} -- one table for every atext, not one per cell per frame

local function barsFor(session)
    local sessionBars = barsBySession[session]
    if not sessionBars then
        sessionBars = {}
        barsBySession[session] = sessionBars
    end
    return sessionBars
end

-- ---------------------------------------------------------------- one button

-- The cell's fill and ring are its :stock, painted by the client (a theme can restyle them). This draws
-- what only the addon knows: the slot's icon, the cooldown pie and the key in the corner (none while unbound).
local function paintCell(session, barNumber, slotIndex, drawEvent)
    local graphics = drawEvent:g()
    local slot = Slots.get(session, barNumber, slotIndex)

    if slot and not slot:empty() then
        local heldEntry = slot:hold() -- an addon's menu entry has no client resource; it carries its own icon
        if heldEntry then
            local icon = heldEntry:icon()
            if icon then
                graphics:image(icon, 1, 1, Layout.ICON, Layout.ICON)
            end
        else
            local resourceName = slot:res()
            if resourceName then
                graphics:resource(resourceName, 1, 1, Layout.ICON, Layout.ICON)
            end
        end

        local cooldown = slot:cooldown()
        if cooldown and cooldown > 0 then
            local color = Layout.COOLDOWN_COLOR
            graphics:color(color[1], color[2], color[3], color[4])
            graphics:prect(1 + (Layout.ICON / 2), 1 + (Layout.ICON / 2), Layout.ICON / 2, cooldown)
            graphics:color()
        end
    end

    local label = Hotkeys.label(barNumber, slotIndex)
    if label then
        graphics:atext(label, Layout.SQUARE - 3, Layout.SQUARE - 1, 1, 1, LABEL_STYLE)
    end
end

-- ---------------------------------------------------------------- the bar's input

-- Widget.Event.dispatch runs the bar's listeners before descending into its children, so this sees every
-- press before the grip does. A press consumed here never reaches the drag; one left alone picks the bar up.
local function onPress(session, barNumber, upright, event)
    local slotIndex = Layout.slotAt(upright, event:x(), event:y())
    local slot = slotIndex and Slots.get(session, barNumber, slotIndex)

    -- A right press is the bar's wherever it lands, so the map underneath never sees it. On a button: a
    -- slot held for an addon's entry is handed back (client-side, at once), any other is cleared (a server
    -- round trip). Clearing a held slot would take the server's content under the hold, so the order matters.
    if event:button() ~= 1 then
        event:preventDefault()
        if not slot then
            return
        end
        local ok, failure = pcall(function()
            if slot:hold() then
                slot:hold(nil)
            else
                slot:clear()
            end
        end)
        if not ok then
            hafen.log():write(failure)
        end
        return
    end

    -- A left press is the button's only when it has something to fire. The frame, the margin, the gutters
    -- and an empty button fall through to the grip, so a bar with nothing on it drags end to end.
    if not (slot and not slot:empty()) then
        return
    end
    event:preventDefault()
    Slots.use(slot)
end

-- A drag out of the action menu: thing = {kind = "pagina", res = <resource>}. An "addon/..." resource is a
-- menu entry an addon added (any addon's; the bar is one shared surface): the slot is held for it
-- client-side, the server never hears. Anything else is written to the slot and echoed back by the server.
local function onDrop(session, barNumber, upright, event)
    local slotIndex = Layout.slotAt(upright, event:x(), event:y())
    if not slotIndex then
        return
    end
    local thing = event:thing()
    if not (thing and thing.kind == "pagina") then
        return
    end
    event:preventDefault()
    if not session:exists() then
        return
    end

    if not thing.res then
        hafen.log():write("Actionbars: that action's resource has not loaded yet -- drop it again in a moment")
        return
    end

    local slot = Slots.get(session, barNumber, slotIndex)
    local ok, failure = pcall(function()
        if thing.res:sub(1, 6) == "addon/" then
            local entry = session:menugrid():get(thing.res)
            if entry then
                slot:hold(entry)
            end
        else
            slot:res(thing.res)
        end
    end)
    if not ok then
        hafen.log():write(failure)
    end
end

-- MouseMove reaches every widget, pointer outside included. Off the box there is nothing to look up, and
-- `showTooltip` writes only when the text changes, so a pointer on the map costs the two coordinate reads.
local function onMove(session, barNumber, upright, boxWidth, boxHeight, showTooltip, event)
    local x, y = event:x(), event:y()
    if x < 0 or y < 0 or x >= boxWidth or y >= boxHeight then
        showTooltip("")
        return
    end
    local slotIndex = Layout.slotAt(upright, x, y)
    local slot = slotIndex and Slots.get(session, barNumber, slotIndex)
    local slotName = slot and (not slot:empty()) and slot:name()
    if slotName then
        showTooltip(slotName)
    elseif barNumber == Layout.MAIN_BAR and (not slotIndex) and session:exists() then
        -- The one bar that pages: on its frame, say which page it shows.
        showTooltip("Actionbar1 -- page " .. session:actionbar():page())
    else
        showTooltip("")
    end
end

-- ---------------------------------------------------------------- build and destroy

function Bars.destroy(session, barNumber)
    local sessionBars = barsBySession[session]
    local barWidget = sessionBars and sessionBars[barNumber]
    if not barWidget then
        return
    end
    sessionBars[barNumber] = nil
    if barWidget:exists() then
        barWidget:destroy() -- the grip and the cells are its children and go with it
    end
end

function Bars.build(session, barNumber)
    local sessionBars = barsFor(session)
    if sessionBars[barNumber] then
        return
    end
    local hud = session:exists() and session:ui():match("@GameUI")
    if not hud then
        return
    end

    local upright = Options.isUpright(barNumber)
    local boxWidth, boxHeight = Layout.barBox(upright)
    local hudSize = hud:size()
    local record = Positions.recordFor(barNumber, boxWidth, boxHeight, hudSize.w, hudSize.h)

    local barWidget = hafen.ui():widget():parent(hud):size(boxWidth, boxHeight):position(record.x, record.y)

    -- The grip covers the whole bar and draws nothing. onPress runs first and consumes presses on loaded
    -- buttons; what is left (frame, margin, gutters, empty buttons) reaches the grip and drags the bar.
    local grip = hafen.ui():widget():parent(barWidget):size(boxWidth, boxHeight):position(0, 0)
    barWidget:draggable(grip)

    -- :name is the selector a theme reaches the bar by ([name=actionbars/bar]). :stock is the look when no
    -- rule names it, at the bottom of the cascade, so a theme's rule wins per property. A widget:rule()
    -- would sit at the top where no theme could reach past it.
    barWidget:name("bar")
    barWidget:stock{bg = {color = Layout.BAR_BACKGROUND}, border = {box = Layout.FRAME_BOX, mode = "tile"}}

    -- One widget per button, named slot1..slot12 so a theme can address one. Subscribed to Draw only: a
    -- surface with no input handler is transparent to the mouse, so presses and drops still land on the bar.
    for slotIndex = 1, Layout.SLOTS_PER_BAR do
        local x, y = Layout.slotOrigin(upright, slotIndex)
        local cell = hafen.ui():widget():parent(barWidget):size(Layout.SQUARE, Layout.SQUARE):position(x, y)
            :name("slot" .. slotIndex)
        cell:stock{bg = {color = Layout.SLOT_FILL}, border = {color = Layout.SLOT_EDGE, width = 1}}
        cell:on("Draw", function(drawEvent)
            paintCell(session, barNumber, slotIndex, drawEvent)
        end)
    end

    barWidget:on("MouseDown", function(event)
        onPress(session, barNumber, upright, event)
    end)
    local tooltipShown = ""
    local function showTooltip(text)
        if text ~= tooltipShown then
            tooltipShown = text
            barWidget:tooltip(text)
        end
    end
    barWidget:on("MouseMove", function(event)
        onMove(session, barNumber, upright, boxWidth, boxHeight, showTooltip, event)
    end)
    barWidget:on("Drop", function(event)
        onDrop(session, barNumber, upright, event)
    end)
    barWidget:on("Dragged", function(event)
        -- event:x()/y() is where it landed, the client's clamp included. Saved now; every other login's
        -- copy follows.
        local dragged = Positions.find(barNumber)
        if not dragged then
            return
        end
        dragged.x, dragged.y = event:x(), event:y()
        Positions.save()
        Bars.moveEverywhere(barNumber)
    end)

    sessionBars[barNumber] = barWidget
end

-- One login's bars in line with the options: build what is on, destroy what is off. A bar whose widget died
-- with a HUD torn down and rebuilt inside one login (leaving the world and coming back) is built again.
function Bars.sync(session)
    local sessionBars = barsFor(session)
    for barNumber, barWidget in pairs(sessionBars) do
        if (not Options.isOn(barNumber)) or (not barWidget:exists()) then
            Bars.destroy(session, barNumber)
        end
    end
    for barNumber = 1, Layout.MAX_BARS do
        if Options.isOn(barNumber) then
            Bars.build(session, barNumber)
        end
    end
end

-- A login that ended took its widgets with the tree.
function Bars.forgetDeadSessions()
    for session in pairs(barsBySession) do
        if not session:exists() then
            barsBySession[session] = nil
        end
    end
end

-- Every login's copy of one bar to its record.
function Bars.moveEverywhere(barNumber)
    local record = Positions.find(barNumber)
    if not record then
        return
    end
    for _, sessionBars in pairs(barsBySession) do
        local barWidget = sessionBars[barNumber]
        if barWidget and barWidget:exists() then
            barWidget:position(record.x, record.y)
        end
    end
end

-- Rotating calls this: the box changes and the grip with it, so the bar is rebuilt rather than resized.
function Bars.destroyEverywhere(barNumber)
    for session in pairs(barsBySession) do
        Bars.destroy(session, barNumber)
    end
end
