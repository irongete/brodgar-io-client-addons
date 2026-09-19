-- One window per login, hung on that login's @GameUI: built on SessionEnteredWorld, gone with the HUD. Two
-- windows are never drawn at once because the client draws one session's tree.
--
-- The window record:
--   session, hud, root          the login, its HUD, and the invisible box holding the strip and the panel
--   grip, panel, log, entry     drag handle, field, lines, entry line
--   frame[3], jointLeft/Right   the frame's three clip boxes (tabs.lua cutFrame) and the joints beside the mouth
--   selected                    the plate under the selected tab's name (tabs.lua buildSelected)
--   sizer                       the resize handle
--   tabs, scroll, lines, signature    tabs.lua / log.lua state
--   shape, laidOut, told        the layout fold
--   hiddenChat, chatWasShown, beltSubscription    clientchat.lua state

local Layout = SimpleChat.Layout
local ClientChat = SimpleChat.ClientChat
local Tabs = SimpleChat.Tabs
local Log = SimpleChat.Log

local Window = {}
SimpleChat.Window = Window

local saved = hafen.store():var("window") -- x, y, w, h: one box for every character on the account

-- Keeps the whole window inside the HUD (the client's own rule keeps 100 px of it). Runs every frame, so a
-- drag is bounded as it happens.
local function clampOnScreen(window)
    local screen = window.hud:exists() and window.hud:size()
    if not (screen and screen.w > 0 and screen.h > 0) then
        return
    end
    local position, box = window.root:position(), window.root:size()
    local x = math.max(0, math.min(position.x, screen.w - box.w))
    local y = math.max(0, math.min(position.y, screen.h - box.h))
    if x ~= position.x or y ~= position.y then
        window.root:position(x, y)
    end
end

local function remember(window)
    clampOnScreen(window)
    local position, box = window.root:position(), window.root:size()
    saved.x, saved.y, saved.w, saved.h = position.x, position.y, box.w, box.h
end

-- The entry's height is its art's, unknown until the tick after it is built.
local function entryHeight(window)
    local box = window.entry:size()
    return (box and box.h and box.h > 0) and box.h or Layout.ENTRY_HEIGHT
end

local function relayout(window)
    local box = window.root:size()
    local pad = Layout.PAD
    local panelHeight = math.max(1, box.h - Layout.STRIP - Layout.SEAT) -- the field starts SEAT below the frame
    local lineHeight = entryHeight(window)
    window.grip:size(box.w, box.h)
    window.panel:position(0, Layout.STRIP + Layout.SEAT):size(box.w, panelHeight)
    window.log:position(pad, pad)
        :size(math.max(1, box.w - (pad * 2)), math.max(1, panelHeight - (pad * 2) - Layout.GAP - lineHeight))
    window.entry:position(pad, panelHeight - pad - lineHeight):size(math.max(1, box.w - (pad * 2)))
    window.sizer:position(box.w - Layout.SIZER, box.h - Layout.SIZER)
    window.signature = nil
    Tabs.place(window)
end

-- Every frame. Re-lays out when the box or the entry height moved. The client's chat is taken only once a
-- layout has landed, so a window that cannot lay itself out never hides the chat its error is written to.
local function tick(window)
    if not window.root:exists() then
        return
    end
    ClientChat.keepAway(window)
    clampOnScreen(window)
    local box = window.root:size()
    local shape = box.w .. "x" .. box.h .. "@" .. entryHeight(window)
    if shape == window.shape then
        return
    end
    local ok, failure = pcall(relayout, window)
    if ok then
        window.shape = shape
        if not window.laidOut then
            window.laidOut = true
            ClientChat.take(window)
        end
    elseif not window.told then
        window.told = true
        hafen.log():write("simple-chat could not lay its window out: " .. tostring(failure))
    end
end

function Window.build(session)
    local hud = session:exists() and session:ui():match("@GameUI")
    if not hud then
        return
    end
    local pad = Layout.PAD
    local width = math.max(Layout.MIN_WIDTH, saved.w or Layout.DEFAULT_WIDTH)
    local height = math.max(Layout.MIN_HEIGHT, saved.h or Layout.DEFAULT_HEIGHT)
    local frameHeight = height - Layout.STRIP
    local panelHeight = frameHeight - Layout.SEAT

    local window = {session = session, hud = hud, frame = {}, tabs = {}, lines = {}, scroll = 0}
    window.root = hafen.ui():widget():parent(hud):size(width, height)
        :position(saved.x or Layout.DEFAULT_X, saved.y or Layout.DEFAULT_Y)
    SimpleChat.windows[session] = window -- from here on there is something for drop to tidy

    -- Children are hit last-added first: the grip goes first, so every control above it takes its own press.
    window.grip = hafen.ui():widget():parent(window.root):position(0, 0):size(width, height)
    window.root:draggable(window.grip)

    -- The field alone; the frame is separate because it needs a hole under the selected tab.
    window.panel = hafen.ui():widget():parent(window.root):position(0, Layout.STRIP + Layout.SEAT)
        :size(width, panelHeight):name("panel")
    window.panel:stock{bg = {color = Layout.FIELD}}

    -- No background and no MouseDown: a press on the lines falls through to the grip. Built at ENTRY_HEIGHT;
    -- the first tick re-lays it out at the entry's real height.
    local logHeight = panelHeight - (pad * 2) - Layout.GAP - Layout.ENTRY_HEIGHT
    window.log = hafen.ui():widget():parent(window.panel):position(pad, pad):name("log")
        :size(math.max(1, width - (pad * 2)), math.max(1, logHeight))
    window.log:on("Draw", function(drawEvent) Log.paint(window, drawEvent) end)
    window.log:on("Wheel", function(wheelEvent)
        local channel = SimpleChat.selectedChannel(window)
        local count = channel and channel:message():count() or 0
        window.scroll = math.max(0, math.min(math.max(0, count - 1), window.scroll - wheelEvent:amount()))
        wheelEvent:preventDefault()
    end)

    -- On the System tab the line runs as a console command of this login (one leading colon dropped, since
    -- the colon only opens the client's command line); on every other tab it is said in the channel.
    window.entry = hafen.ui():entry():parent(window.panel):position(pad, panelHeight - pad - Layout.ENTRY_HEIGHT)
        :size(math.max(1, width - (pad * 2)))
    window.entry:on("Submitted", function(text)
        window.entry:value("")
        local channel = SimpleChat.selectedChannel(window)
        if not (text and text ~= "" and channel) then
            return
        end
        local ok, failure
        if channel:kind() == "chat.system" then
            local line = text:gsub("^%s*:?%s*", "")
            if line == "" then
                return
            end
            ok, failure = pcall(function() window.session:console():run(line) end)
        else
            ok, failure = pcall(function() channel:send(text) end)
        end
        if not ok then
            hafen.log():write(failure)
        end
        window.scroll = 0
    end)

    -- The frame: three clip boxes, each holding the same full-size nine-slice (tabs.lua cutFrame). After the
    -- panel and before the tabs, so it is drawn over the field and under the tabs.
    for index = 1, 3 do
        local clip = hafen.ui():widget():parent(window.root):position(0, Layout.STRIP):size(width, frameHeight)
        local ink = hafen.ui():widget():parent(clip):position(0, 0):size(width, frameHeight):name("frame")
        ink:stock{border = {box = Layout.FRAME_BOX}}
        window.frame[index] = {clip = clip, ink = ink}
    end
    window.jointLeft = hafen.ui():widget():parent(window.root):position(pad, Layout.STRIP)
        :size(Layout.RUN, Layout.RUN):name("jointLeft"):visible(false)
    window.jointLeft:stock{bg = {asset = Layout.JOINT_LEFT_ASSET}}
    window.jointRight = hafen.ui():widget():parent(window.root):position(pad, Layout.STRIP)
        :size(Layout.RUN, Layout.RUN):name("jointRight"):visible(false)
    window.jointRight:stock{bg = {asset = Layout.JOINT_RIGHT_ASSET}}

    -- The selected tab's plate, after the joints: it seats on the frame's top row, where they start.
    Tabs.buildSelected(window)

    -- Three strokes across the frame's corner, as the client's own sizer: a stock, so a theme's corner replaces
    -- them rather than sitting under them. On the root, after the frame: a frame paints over its own contents.
    window.sizer = hafen.ui():widget():parent(window.root):position(width - Layout.SIZER, height - Layout.SIZER)
        :size(Layout.SIZER, Layout.SIZER):name("sizer")
    window.sizer:stock{bg = {asset = Layout.SIZER_ASSET}}
    window.root:resizable(window.sizer)

    window.root:on("Update", function() tick(window) end)
    window.root:on("Dragged", function() remember(window) end)
    window.root:on("Resized", function()
        local box = window.root:size()
        local newWidth, newHeight = math.max(Layout.MIN_WIDTH, box.w), math.max(Layout.MIN_HEIGHT, box.h)
        -- ...and no bigger than the room left on the screen, or the far side would be pushed off it.
        local position, screen = window.root:position(), window.hud:exists() and window.hud:size()
        if screen and screen.w > 0 and screen.h > 0 then
            newWidth = math.min(newWidth, math.max(Layout.MIN_WIDTH, screen.w - position.x))
            newHeight = math.min(newHeight, math.max(Layout.MIN_HEIGHT, screen.h - position.y))
        end
        if newWidth ~= box.w or newHeight ~= box.h then
            window.root:size(newWidth, newHeight)
        end
        remember(window) -- the layout follows on the next tick
    end)

    ClientChat.hookBeltButton(window)
    Tabs.build(window)
end

-- Destroys the window and gives the client's chat back.
function Window.drop(session)
    local window = SimpleChat.windows[session]
    if not window then
        return
    end
    SimpleChat.windows[session] = nil
    ClientChat.giveBack(window)
    if window.beltSubscription then
        pcall(function() window.beltSubscription:off() end)
    end
    if window.root:exists() then
        window.root:destroy()
    end
end

-- Replaces the session's window. A build that throws is torn down and logged; nothing of the client's is
-- taken before the first layout, so the player keeps the client's chat.
function Window.raise(session)
    Window.drop(session)
    local ok, failure = pcall(Window.build, session)
    if not ok then
        hafen.log():write("simple-chat could not build its window: " .. tostring(failure))
        Window.drop(session)
    end
end
