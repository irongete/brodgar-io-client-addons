-- The lines of the selected channel, newest at the bottom, wrapped to the log widget's box. `window.scroll`
-- is how many lines up from the newest the view is parked; 0 follows the newest.

local Layout = SimpleChat.Layout

local Log = {}
SimpleChat.Log = Log

-- Lays out the lines that fit `height`, walking back from the parked line. measure reads the same markup the
-- draw does, so the wrap is the client's own.
local function layout(window, channel, width, height, count)
    local lines = {}
    local messages = channel:message()
    local used = 0
    local index = count - window.scroll
    while index >= 1 and used < height do
        local message = messages:get(index)
        if not message then
            break
        end
        local text = message:text() or "" -- the line alone: the speaker is drawn back in front of it
        local speaker = message:speaker()
        if speaker then
            text = (speaker:name() or "?") .. ": " .. text
        end
        local measured = hafen.ui():measure(text, {width = width})
        table.insert(lines, 1, {text = text, height = measured.h, color = message:color()})
        used = used + measured.h + Layout.GAP
        index = index - 1
    end
    window.lines = lines
end

-- The log's Draw handler. Re-laid out only when the channel, its count, the box or the scroll moved.
function Log.paint(window, drawEvent)
    local channel = SimpleChat.selectedChannel(window)
    if not channel then
        return
    end
    local width, height = drawEvent:w(), drawEvent:h()
    local count = channel:message():count()
    local signature = tostring(channel) .. ":" .. count .. ":" .. width .. ":" .. height .. ":" .. window.scroll
    if signature ~= window.signature then
        window.signature = signature
        layout(window, channel, width, height, count)
    end
    local graphics = drawEvent:g()
    local y = height
    for index = #window.lines, 1, -1 do
        local line = window.lines[index]
        y = y - line.height - Layout.GAP
        graphics:text(line.text, 0, y, {width = width, color = line.color or Layout.TEXT})
    end
end
