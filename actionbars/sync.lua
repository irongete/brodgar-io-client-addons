-- The bars follow the options: per login, the client's own belt is hidden and the bars built or destroyed;
-- hotkeys are declared for the bars that are on. Reset puts every bar back mid-screen.

local Layout = Actionbars.Layout
local Positions = Actionbars.Positions
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

function Sync.syncAll()
    Bars.forgetDeadSessions()
    for _, session in ipairs(hafen.session():list()) do
        Sync.syncSession(session)
    end
    for barNumber = 1, Layout.MAX_BARS do
        if Options.isOn(barNumber) then
            Hotkeys.bind(barNumber)
        else
            Hotkeys.unbind(barNumber)
        end
    end
    Hotkeys.refreshLabels() -- after the declarations: an undeclared binding reads no key
end

-- ---------------------------------------------------------------- reset

-- The HUD's size in design px (bar x/y are measured from it), from any login in the world.
local function screenSize()
    for _, session in ipairs(hafen.session():list()) do
        if session:exists() then
            local hud = session:ui():match("@GameUI")
            local size = hud and hud:size()
            if size and size.w > 0 and size.h > 0 then
                return size.w, size.h
            end
        end
    end
    return nil
end

-- Every bar that is on, centred as one stack in number order, and saved. A higher interface scale or a
-- smaller window can leave a bar past the edge with no part of it left to drag; this is the way back.
function Sync.resetBars()
    local screenWidth, screenHeight = screenSize()
    if not screenWidth then
        Options.showStatus("no character is in the world, so there is no screen to measure and no bar drawn"
            .. " to put back on it")
        return
    end

    local stackHeight = 0
    for barNumber = 1, Layout.MAX_BARS do
        if Options.isOn(barNumber) then
            local _, boxHeight = Layout.barBox(Options.isUpright(barNumber))
            if stackHeight > 0 then
                stackHeight = stackHeight + Layout.STACK_GAP
            end
            stackHeight = stackHeight + boxHeight
        end
    end

    local y = math.max(0, math.floor((screenHeight - stackHeight) / 2))
    for barNumber = 1, Layout.MAX_BARS do
        if Options.isOn(barNumber) then
            local boxWidth, boxHeight = Layout.barBox(Options.isUpright(barNumber))
            local record = Positions.recordFor(barNumber, boxWidth, boxHeight, screenWidth, screenHeight)
            local centredX = Positions.centre(boxWidth, boxHeight, screenWidth, screenHeight)
            record.x = centredX
            record.y = y
            y = y + boxHeight + Layout.STACK_GAP
            Bars.moveEverywhere(barNumber)
        end
    end
    Positions.save()
    Options.showStatus("every bar is back in the middle of the screen")
end
