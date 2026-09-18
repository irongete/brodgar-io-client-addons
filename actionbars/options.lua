-- Which bars are on and which way they stand: one choice option per bar in the client's preference store,
-- shown as twelve dropdowns on Options > AddOns > Actionbars. The addon has no window of its own.
-- A bar's number is its identity (Actionbar4 is always slots 37-48), so there are twelve fixed rows and no
-- Add button.

local Layout = Actionbars.Layout
local Positions = Actionbars.Positions

local Options = {}
Actionbars.Options = Options

Options.OFF = "off"
Options.FLAT = "flat"
Options.UPRIGHT = "upright"

local addonOptions = hafen.client():options():addon()
local barOptions = {} -- [barNumber] = the choice option

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

-- A label never wraps: the intro is a bare surface as wide as the page drawing wrapped text. Measured
-- first so the surface is as tall as the lines; +2 px keeps a descender on the last line from clipping.
local function addParagraph(root, text)
    local style = {width = root:size().w - 8}
    local box = hafen.ui():measure(text, style)
    local surface = hafen.ui():widget():parent(root):size(style.width, box.h + 2)
    surface:on("Draw", function(drawEvent)
        drawEvent:g():text(text, 0, 0, style)
    end)
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

-- Rebuilt on every visit; nothing built here is kept but statusLabel.
addonOptions:panel(function(root)
    root:gap(4)
    addParagraph(root, "A bar is one page of the belt: ActionbarN is slots (N-1)x12+1 to Nx12. Actionbar1"
        .. " follows the page you are on, in place of the client's own bar.")
    for barNumber = 1, Layout.MAX_BARS do
        local row = hafen.ui():row():gap(6):parent(root)
        hafen.ui():dropdown():parent(row):size(90):tooltip(rowTooltip(barNumber)):bind(barOptions[barNumber])
        -- 3 px down: level with the dropdown beside it
        hafen.ui():label():parent(row):text("Actionbar" .. barNumber):rule():margin(0, 3, 0, 0)
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

-- A changed row: the bar is rebuilt everywhere (a rotation is a different box) and the rest re-synced.
for barNumber = 1, Layout.MAX_BARS do
    barOptions[barNumber]:on("Changed", function()
        runNextStep(function()
            Actionbars.Bars.destroyEverywhere(barNumber)
            Actionbars.Sync.syncAll()
            Options.showStatus()
        end)
    end)
end
