-- Which bars are on, which way they stand and how many buttons each shows: a choice option and a number
-- option per bar in the client's preference store, shown as twelve rows (a dropdown and a slider) on
-- Options > AddOns > Actionbars. The addon has no window of its own. A bar's number is its identity
-- (Actionbar4 is always slots 37-48), so there are twelve fixed rows and no Add button.

local Layout = Actionbars.Layout
local Positions = Actionbars.Positions

local Options = {}
Actionbars.Options = Options

Options.OFF = "off"
Options.FLAT = "flat"
Options.UPRIGHT = "upright"

local addonOptions = hafen.client():options():addon()
local barOptions = {} -- [barNumber] = the choice option: off, flat or upright
local buttonOptions = {} -- [barNumber] = the number option: how many of the bar's slots it shows, 1..12

-- A bar with a saved place had been turned on by the version before the options: it seeds its own row.
local function defaultMode(barNumber)
    local legacyUpright = Positions.legacyUpright(barNumber)
    if legacyUpright == true then
        return Options.UPRIGHT
    end
    if legacyUpright == false then
        return Options.FLAT
    end
    if barNumber == Layout.MAIN_BAR then
        return Options.FLAT
    end
    return Options.OFF
end

for barNumber = 1, Layout.MAX_BARS do
    local choices = {Options.OFF, Options.FLAT, Options.UPRIGHT}
    if barNumber == Layout.MAIN_BAR then
        choices = {Options.FLAT, Options.UPRIGHT} -- stands in for the client's own bar: never off
    end
    barOptions[barNumber] = addonOptions:choice("bar" .. barNumber)
        :choices(choices)
        :default(defaultMode(barNumber))
        :add()
    buttonOptions[barNumber] = addonOptions:number("bar" .. barNumber .. "buttons")
        :range(1, Layout.SLOTS_PER_BAR)
        :default(Layout.SLOTS_PER_BAR)
        :add()
end

function Options.mode(barNumber)
    return barOptions[barNumber]:value()
end

function Options.isOn(barNumber)
    return Options.mode(barNumber) ~= Options.OFF
end

function Options.isUpright(barNumber)
    return Options.mode(barNumber) == Options.UPRIGHT
end

-- How many of the bar's twelve slots it shows, from the first.
function Options.buttonCount(barNumber)
    return buttonOptions[barNumber]:value()
end

function Options.countOn()
    local count = 0
    for barNumber = 1, Layout.MAX_BARS do
        if Options.isOn(barNumber) then
            count = count + 1
        end
    end
    return count
end

-- A handler on the page runs inside the widget tree of the login that opened Options; the bars stand in
-- every login's HUD, and the client refuses to hold two trees at once. The work runs on the next step.
local function runNextStep(work)
    hafen.timer():after(0, work)
end

-- ---------------------------------------------------------------- the page

local statusLabel -- the line under the rows; nil or dead while the page is closed

-- How many bars are on, plus `message` (what the last press did).
function Options.showStatus(message)
    local count = Options.countOn()
    local line = count .. " of " .. Layout.MAX_BARS .. " bars on"
    if count >= Layout.MAX_BARS then
        line = line .. " -- 144 slots is every one there is"
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
    local count = Options.buttonCount(barNumber)
    if count == 1 then
        return "1 button"
    end
    return count .. " buttons"
end

-- Rebuilt on every visit; nothing built here is kept but statusLabel.
addonOptions:panel(function(root)
    root:gap(4)
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
        :tooltip("put every bar back in the middle of the screen, stacked -- for when one has ended up past an"
            .. " edge and there is nothing left to drag")
    resetButton:on("Pressed", function()
        runNextStep(Actionbars.Sync.resetBars)
    end)
    statusLabel = hafen.ui():label():parent(root):text("")
    Options.showStatus()
end)

-- A changed row: the bar is rebuilt everywhere (a rotation or another button count is a different box)
-- and the rest re-synced. A slider drag reports every step; the steps that land on one engine step are
-- rebuilt once.
local rebuildPending = {} -- [barNumber] = true while a rebuild is queued for the next step

local function rebuildNextStep(barNumber)
    if rebuildPending[barNumber] then
        return
    end
    rebuildPending[barNumber] = true
    runNextStep(function()
        rebuildPending[barNumber] = nil
        Actionbars.Bars.destroyEverywhere(barNumber)
        Actionbars.Sync.syncAll()
        Options.showStatus()
    end)
end

for barNumber = 1, Layout.MAX_BARS do
    barOptions[barNumber]:on("Changed", function()
        rebuildNextStep(barNumber)
    end)
    buttonOptions[barNumber]:on("Changed", function()
        rebuildNextStep(barNumber)
    end)
end
