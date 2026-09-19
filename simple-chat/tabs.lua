-- One bare widget per channel, parented to the root (not the panel) so the strip can stand on the frame, and
-- one more for whichever channel is selected: `window.selected`, a plate place moves under the selected tab's
-- name while that tab's own widget is hidden. Two surfaces rather than one re-dressed, because a theme names
-- what a widget IS and not the state it is in: `[name^=simple-chat/tab]` is every tab that is not being read
-- and `[name=simple-chat/selected]` the one that is, each with a stock of its own. Widgets are created and
-- destroyed on the channel events, outside the Update walk; place only moves and shows the ones that exist.

local Layout = SimpleChat.Layout
local ClientChat = SimpleChat.ClientChat

local Tabs = {}
SimpleChat.Tabs = Tabs

-- The name cut to `width` with an ellipsis, measured with the font drawn. Never cuts inside a UTF-8 sequence.
local function fit(name, width)
    if hafen.ui():measure(name, {}).w <= width then
        return name
    end
    for cut = #name, 1, -1 do
        local nextByte = name:byte(cut + 1)
        if not (nextByte and nextByte >= 128 and nextByte < 192) then
            local short = name:sub(1, cut) .. Layout.ELLIPSIS
            if hafen.ui():measure(short, {}).w <= width then
                return short
            end
        end
    end
    return ""
end

-- The stock draws plate and frame; this draws the name on the row every tab starts on, and the close X on the
-- selected private tab, as the client's own chat carries one. Drawn in whatever font a rule on the widget
-- says; the colours are tints, so a rule's colour composes with them rather than replacing them.
local function paintName(graphics, channel, width, isSelected)
    local color = Layout.TEXT
    if (channel:urgency() or 0) > 0 then
        color = Layout.UNREAD
    elseif not isSelected then
        color = Layout.DIM
    end
    local room = width - (Layout.RUN * 2) - 2 -- inside the two runs, a pixel of air off them
    if isSelected and channel:kind() == "chat.private" then
        room = room - Layout.CLOSE_WIDTH
        graphics:atext(Layout.CLOSE_GLYPH, width - Layout.RUN - (Layout.CLOSE_WIDTH / 2), Layout.TAB_HEIGHT / 2,
            0.5, 0.5, {color = Layout.DIM})
    end
    graphics:atext(fit(channel:name() or "?", room), Layout.RUN + 1 + (room / 2), Layout.TAB_HEIGHT / 2, 0.5, 0.5,
        {color = color})
end

-- The frame is one nine-slice drawn through three clip boxes: the top edge left of the mouth, right of it, and
-- everything below the top edge. The stretch no box shows is the selected tab's mouth: a nine-slice cannot cut
-- a hole, and the field is translucent, so paint could not hide the run. mouthLeft == mouthRight leaves it whole.
local function cutFrame(window, mouthLeft, mouthRight)
    local box = window.root:size()
    local frameHeight = math.max(1, box.h - Layout.STRIP)
    local function clipTo(index, x, y, width, height)
        local frame = window.frame[index]
        if width < 1 or height < 1 then
            frame.clip:visible(false)
            return
        end
        frame.clip:visible(true)
        frame.clip:position(x, Layout.STRIP + y):size(width, height)
        frame.ink:position(-x, -y):size(box.w, frameHeight) -- cancels the clip's own offset
    end
    mouthLeft, mouthRight = math.min(mouthLeft, box.w), math.min(mouthRight, box.w)
    clipTo(1, 0, 0, mouthLeft, Layout.HOLE_HEIGHT)
    clipTo(2, mouthRight, 0, box.w - mouthRight, Layout.HOLE_HEIGHT)
    clipTo(3, 0, Layout.HOLE_HEIGHT, box.w, frameHeight - Layout.HOLE_HEIGHT)
end

-- Places every tab on the strip's row. Tabs share the width down to TAB_MIN_WIDTH; past that the ones that do
-- not fit are hidden. The selected tab's own widget is hidden too, and the selected plate stands in its place,
-- taller (down to the frame, SEAT deeper); the frame is cut for its width.
function Tabs.place(window)
    if not window.root:exists() then
        return
    end
    local width = window.root:size().w
    local selected = SimpleChat.selectedChannel(window)
    local tabCount = #window.tabs
    local tabWidth = math.floor((width - (Layout.PAD * 2) - (Layout.GAP * (tabCount - 1))) / math.max(1, tabCount))
    tabWidth = math.max(Layout.TAB_MIN_WIDTH, math.min(Layout.TAB_MAX_WIDTH, tabWidth))
    local mouthLeft, mouthRight = width, width
    local selectedFits = false
    for index, tab in ipairs(window.tabs) do
        local isSelected = tab.channel == selected
        local x = Layout.PAD + ((index - 1) * (tabWidth + Layout.GAP))
        local fits = (x + tabWidth) <= (width - Layout.PAD)
        tab.widget:visible(fits and not isSelected)
        tab.widget:position(x, Layout.TAB_DROP):size(tabWidth, Layout.TAB_HEIGHT)
        if fits and isSelected then
            mouthLeft, mouthRight = x, x + tabWidth
            window.selected:position(x, Layout.TAB_DROP):size(tabWidth, Layout.TAB_ON_HEIGHT + Layout.SEAT)
            window.jointLeft:position(x, Layout.STRIP)
            window.jointRight:position(x + tabWidth - Layout.RUN, Layout.STRIP)
            selectedFits = true
        end
    end
    window.selected:visible(selectedFits)
    window.jointLeft:visible(selectedFits)
    window.jointRight:visible(selectedFits)
    cutFrame(window, mouthLeft, mouthRight)
end

-- The selected tab's plate: built once with the window (window.lua), on the root after the joints so it paints
-- over them where it seats on the frame. It draws the selected channel's name and, on a private one, the X
-- that closes it. A press anywhere else on it stays there: the channel is selected already.
function Tabs.buildSelected(window)
    local selected = hafen.ui():widget():parent(window.root):position(Layout.PAD, Layout.TAB_DROP)
        :size(Layout.TAB_MIN_WIDTH, Layout.TAB_ON_HEIGHT + Layout.SEAT):name("selected"):visible(false)
    selected:stock{
        bg = {color = Layout.FIELD},
        border = {asset = Layout.TAB_ON_ASSET, slice = Layout.TAB_ON_SLICE},
    }
    selected:on("Draw", function(drawEvent)
        local channel = SimpleChat.selectedChannel(window)
        if channel then
            paintName(drawEvent:g(), channel, drawEvent:w(), true)
        end
    end)
    selected:on("MouseDown", function(mouseEvent)
        local channel = SimpleChat.selectedChannel(window)
        if mouseEvent:button() == 1 and channel and channel:exists() and channel:kind() == "chat.private"
            and mouseEvent:x() >= selected:size().w - Layout.RUN - Layout.CLOSE_WIDTH then
            ClientChat.closePrivate(window, channel)
        end
        mouseEvent:preventDefault()
    end)
    window.selected = selected
end

-- Rebuilds the tab widgets from the channel list, in the client's tab order.
function Tabs.build(window)
    for _, tab in ipairs(window.tabs) do
        if tab.widget:exists() then
            tab.widget:destroy()
        end
    end
    window.tabs = {}
    if not (window.root:exists() and window.session:exists()) then
        return
    end
    for index, channel in ipairs(window.session:chat():list()) do
        local widget = hafen.ui():widget():parent(window.root):position(Layout.PAD, Layout.TAB_DROP)
            :size(Layout.TAB_MIN_WIDTH, Layout.TAB_HEIGHT):name("tab" .. index)
        widget:stock{
            bg = {color = Layout.TAB_FILL},
            border = {asset = Layout.TAB_OFF_ASSET, slice = Layout.TAB_OFF_SLICE},
        }
        local tab = {widget = widget, channel = channel}
        widget:on("Draw", function(drawEvent)
            paintName(drawEvent:g(), channel, drawEvent:w(), false)
        end)
        -- A tab takes its own press, so it does not drag the window under it: the press selects the channel.
        widget:on("MouseDown", function(mouseEvent)
            if mouseEvent:button() == 1 and channel:exists() then
                pcall(function() window.session:chat():selected(channel) end)
                window.scroll = 0
            end
            mouseEvent:preventDefault()
        end)
        window.tabs[index] = tab
    end
    Tabs.place(window)
end
