-- The page on Options > AddOns > Actionbars: twelve rows, one per bar, each a dropdown (off, flat or
-- upright) and a slider (how many buttons, 1..12). The rows edit the bars of the character on screen: a
-- bar's settings are that character's (config.lua), and the client's own options behind the controls are
-- a mirror of the character on screen, loaded whenever the screen changes hands or the page opens. The
-- addon has no window of its own. A bar's number is its identity (Actionbar4 is always slots 37-48), so
-- there are twelve fixed rows and no Add button.

local Layout = Actionbars.Layout
local Config = Actionbars.Config

local Options = {}
Actionbars.Options = Options

local addonOptions = hafen.client():options():addon()
local barOptions = {} -- [barNumber] = the choice option: off, flat or upright, for the character on screen
local buttonOptions = {} -- [barNumber] = the number option: how many of the bar's slots it shows, 1..12

for barNumber = 1, Layout.MAX_BARS do
    local choices = {Config.OFF, Config.FLAT, Config.UPRIGHT}
    if barNumber == Layout.MAIN_BAR then
        choices = {Config.FLAT, Config.UPRIGHT} -- stands in for the client's own bar: never off
    end
    barOptions[barNumber] = addonOptions:choice("bar" .. barNumber)
        :choices(choices)
        :default(Config.mode(nil, barNumber))
        :add()
    buttonOptions[barNumber] = addonOptions:number("bar" .. barNumber .. "buttons")
        :range(1, Layout.SLOTS_PER_BAR)
        :default(Layout.SLOTS_PER_BAR)
        :add()
end

-- The character on screen's settings into the controls. A write of the value held fires nothing, and the
-- Changed handlers below skip a value the character already has, so loading never rebuilds a bar.
function Options.load(session)
    for barNumber = 1, Layout.MAX_BARS do
        barOptions[barNumber]:value(Config.mode(session, barNumber))
        buttonOptions[barNumber]:value(Config.buttonCount(session, barNumber))
    end
end

-- A handler on the page runs inside the widget tree of the login that opened Options; the bars stand in
-- the login's HUD, another tree, and the client refuses to hold two at once. The work runs on the next step.
local function runNextStep(work)
    hafen.timer():after(0, work)
end

-- ---------------------------------------------------------------- the page

local statusLabel -- the line under the rows; nil or dead while the page is closed

-- Whose bars the rows edit and how many are on, plus `message` (what the last press did).
function Options.showStatus(message)
    local session = hafen.session():current()
    local line
    if Config.ready(session) then
        local count = Config.countOn(session)
        line = session:character() .. ": " .. count .. " of " .. Layout.MAX_BARS .. " bars on"
        if count >= Layout.MAX_BARS then
            line = line .. " -- 144 slots is every one there is"
        end
    else
        line = "no character is in the world: the rows have nobody's bars to set"
    end
    if message then
        line = line .. " -- " .. message
    end
    if statusLabel and statusLabel:exists() then
        statusLabel:text(line)
    end
end

local function rowTooltip(barNumber)
    if barNumber == Layout.MAIN_BAR then
        return "the page you are on, lying flat or standing upright -- it stands in for the client's own bar"
            .. " and cannot be taken away"
    end
    local firstSlot = ((barNumber - 1) * Layout.SLOTS_PER_BAR) + 1
    local lastSlot = barNumber * Layout.SLOTS_PER_BAR
    return "slots " .. firstSlot .. "-" .. lastSlot .. " -- off, lying flat, or standing upright"
end

local function buttonsTooltip(barNumber)
    return "how many buttons Actionbar" .. barNumber .. " shows, from its first slot -- the rest of the page"
        .. " keeps what it holds and its hotkeys still fire"
end

local function buttonsText(barNumber)
    local count = buttonOptions[barNumber]:value()
    if count == 1 then
        return "1 button"
    end
    return count .. " buttons"
end

-- Rebuilt on every visit; nothing built here is kept but statusLabel.
addonOptions:panel(function(root)
    Options.load(hafen.session():current())
    root:gap(4)
    hafen.ui():label():parent(root):text("The bars of the character on screen; every character has their own.")
    for barNumber = 1, Layout.MAX_BARS do
        local row = hafen.ui():row():gap(6):parent(root)
        hafen.ui():dropdown():parent(row):size(90):tooltip(rowTooltip(barNumber)):bind(barOptions[barNumber])
        local slider = hafen.ui():slider():parent(row):size(120):tooltip(buttonsTooltip(barNumber))
            :bind(buttonOptions[barNumber])
        -- 3 px down: level with the dropdown beside them. `:rule()` hands back the rule, not the label, so
        -- the label is taken before the margin is set on it.
        local countLabel = hafen.ui():label():parent(row):text(buttonsText(barNumber))
        countLabel:rule():margin(0, 3, 0, 0)
        hafen.ui():label():parent(row):text("Actionbar" .. barNumber):rule():margin(0, 3, 0, 0)
        -- The slider's own report, in the page's tree: the label beside it is the one write made here.
        slider:on("Changed", function()
            if countLabel:exists() then
                countLabel:text(buttonsText(barNumber))
            end
        end)
    end
    local resetButton = hafen.ui():button():parent(root):size(160):text("Reset bars position")
        :tooltip("stack every bar back on the bottom edge of the screen, centred, and forget where they were"
            .. " dragged")
    resetButton:on("Pressed", function()
        runNextStep(Actionbars.Sync.resetBars)
    end)
    statusLabel = hafen.ui():label():parent(root):text("")
    Options.showStatus()
end)

-- A changed row is the character on screen's: written to their settings, and their bar rebuilt (a
-- rotation or another button count is a different box). A slider drag reports every step; the steps that
-- land on one engine step are rebuilt once. A value the character already holds (the controls being
-- loaded) is nothing to do.
local rebuildPending = {} -- [session] = { [barNumber] = true } while a rebuild is queued for the next step

local function rebuildNextStep(session, barNumber)
    local pending = rebuildPending[session]
    if not pending then
        pending = {}
        rebuildPending[session] = pending
    end
    if pending[barNumber] then
        return
    end
    pending[barNumber] = true
    runNextStep(function()
        pending[barNumber] = nil
        Actionbars.Bars.destroy(session, barNumber)
        Actionbars.Sync.syncSession(session)
        Actionbars.Sync.syncHotkeys()
        Options.showStatus()
    end)
end

for barNumber = 1, Layout.MAX_BARS do
    barOptions[barNumber]:on("Changed", function(mode)
        local session = hafen.session():current()
        if not Config.ready(session) then
            Options.showStatus()
            return
        end
        if Config.mode(session, barNumber) ~= mode then
            Config.setMode(session, barNumber, mode)
            rebuildNextStep(session, barNumber)
        end
    end)
    buttonOptions[barNumber]:on("Changed", function(count)
        local session = hafen.session():current()
        if not Config.ready(session) then
            Options.showStatus()
            return
        end
        if Config.buttonCount(session, barNumber) ~= count then
            Config.setButtonCount(session, barNumber, count)
            rebuildNextStep(session, barNumber)
        end
    end)
end
