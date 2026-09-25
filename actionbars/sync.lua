-- The bars follow each character's settings: per login, the client's own belt is hidden and the bars built
-- or destroyed; hotkeys are declared for the bars the character on screen has on, and the options page is
-- loaded with that character's settings. Reset stacks every bar back on the bottom edge.

local Layout = Actionbars.Layout
local Config = Actionbars.Config
local Options = Actionbars.Options
local Hotkeys = Actionbars.Hotkeys
local Bars = Actionbars.Bars

local Sync = {}
Actionbars.Sync = Sync

-- ---------------------------------------------------------------- the client's own bar

-- Actionbar1 shows the page the client's bar starts on; both up would draw the same twelve buttons twice.
-- Its keys stay bound (Options > Keybindings > Action bar) and go on pressing Actionbar1's slots.
-- Two selectors because the client has two views of the bar and `:belt f` switches between them.
local hiddenBelts = {} -- only the widgets this addon hid: Disable gives back these and no others

local function hideClientBelt(session)
    for _, selector in ipairs({"@NKeyBelt", "@FKeyBelt"}) do
        local belt = session:ui():match(selector)
        if belt and belt:visible() then
            local ok, failure = pcall(function()
                belt:visible(false)
            end)
            if ok then
                hiddenBelts[#hiddenBelts + 1] = belt
            else
                hafen.log():write(failure)
            end
        end
    end
end

-- Runs from Disable, before teardown. Teardown's own restore reads a bare hide as "not on screen" and
-- leaves the belt hidden, and the belt has no toggle to reopen it with, so it is shown by hand.
function Sync.restoreClientBelts()
    for _, belt in ipairs(hiddenBelts) do
        if belt:exists() then
            pcall(function()
                belt:visible(true)
            end)
        end
    end
    hiddenBelts = {}
end

-- ---------------------------------------------------------------- sync

function Sync.syncSession(session)
    if not session:exists() then
        return
    end
    hideClientBelt(session)
    Bars.sync(session)
end

-- The hotkeys are the character on screen's: declared for the bars they have on, and the corner labels
-- re-read after the declarations (an undeclared binding reads no key).
function Sync.syncHotkeys()
    local session = hafen.session():current()
    for barNumber = 1, Layout.MAX_BARS do
        if Config.isOn(session, barNumber) then
            Hotkeys.bind(barNumber)
        else
            Hotkeys.unbind(barNumber)
        end
    end
    Hotkeys.refreshLabels()
end

function Sync.syncAll()
    Bars.forgetDeadSessions()
    for _, session in ipairs(hafen.session():list()) do
        Sync.syncSession(session)
    end
    Sync.syncHotkeys()
    Options.load(hafen.session():current())
    Options.showStatus()
end

-- A login entering the world, as a character it may not have played before this session: whatever bars
-- it had are the last character's and go, and its own are built from its settings.
function Sync.enteredWorld(session)
    for barNumber = 1, Layout.MAX_BARS do
        Bars.destroy(session, barNumber)
    end
    Sync.syncAll()
end

-- ---------------------------------------------------------------- reset

-- One character's bars that are on, as one stack centred on the bottom edge: Actionbar1 on the edge and each
-- next bar above the one before. false with no HUD size to measure against (a login not yet in the world,
-- or a HUD with no size).
local function resetSession(session)
    local hud = session:exists() and session:character() and session:ui():match("@GameUI")
    local size = hud and hud:size()
    if not (size and size.w > 0 and size.h > 0) then
        return false
    end

    local bottom = size.h -- where the next bar's bottom edge goes
    for barNumber = 1, Layout.MAX_BARS do
        if Config.isOn(session, barNumber) then
            local boxWidth, boxHeight = Layout.barBox(Config.isUpright(session, barNumber), Config.buttonCount(session, barNumber))
            local x = math.max(0, math.floor((size.w - boxWidth) / 2))
            local y = math.max(0, bottom - boxHeight)
            Config.forgetOldPlace(session, barNumber)
            Bars.resetPlace(session, barNumber, x, y)
            bottom = y - Layout.STACK_GAP
        end
    end
    Config.save(session)
    return true
end

-- Every character in the world gets their bars back on the bottom edge, each measured against their own HUD,
-- and where they had dragged them is forgotten. A character not logged in keeps their places.
function Sync.resetBars()
    local resetCount = 0
    for _, session in ipairs(hafen.session():list()) do
        if resetSession(session) then
            resetCount = resetCount + 1
        end
    end
    if resetCount == 0 then
        Options.showStatus("no character is in the world, so there is no screen to measure and no bar drawn"
            .. " to put back on it")
    elseif resetCount == 1 then
        Options.showStatus("every bar is back on the bottom edge of the screen")
    else
        Options.showStatus("every bar is back on the bottom edge of the screen, on all " .. resetCount
            .. " characters in the world")
    end
end
