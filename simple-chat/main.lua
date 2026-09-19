-- Entry point: session and chat events, the `:simplechat` command and the `toggle` hotkey.

local Window = SimpleChat.Window
local Tabs = SimpleChat.Tabs
local ClientChat = SimpleChat.ClientChat

local function windowOf(session)
    return session and SimpleChat.windows[session]
end

-- Every entry into the world is a new HUD: a fresh login, or the same account picking another character.
-- A :reload announces it for every session already in the world.
hafen.event():on("SessionEnteredWorld", Window.raise)

hafen.event():on("SessionRemoved", function(session)
    SimpleChat.windows[session] = nil -- its tree is gone: nothing to destroy, nothing to give back
end)

for _, key in ipairs({"ChannelAdded", "ChannelRemoved"}) do
    hafen.event():on(key, function(channel, session)
        local window = windowOf(session)
        if window then
            window.scroll = 0
            window.signature = nil
            Tabs.build(window)
        end
    end)
end

hafen.event():on("ChannelSelected", function(channel, session)
    local window = windowOf(session)
    if window then
        window.scroll = 0
        window.signature = nil
        pcall(Tabs.place, window)
    end
end)

-- A line arriving below a scrolled-up view must not shift what is being read.
hafen.event():on("MessageAdded", function(message, session)
    local window = windowOf(session)
    if window and window.scroll > 0 and message:channel() == SimpleChat.selectedChannel(window) then
        window.scroll = window.scroll + 1
    end
end)

-- Disable fires before the teardown, which leaves a bare hide hidden: the client's chats come back here.
hafen.event():on("Disable", function()
    for _, window in pairs(SimpleChat.windows) do
        ClientChat.giveBack(window)
    end
    SimpleChat.windows = {}
end)

-- The window of the character on screen. Both callers run in that character's tree, where the window hangs,
-- so nothing is deferred. The hotkey starts unbound (an addon may not claim a key); assigned Ctrl+C, it
-- shadows the client's `chat-toggle` for as long as the assignment stands, without writing to it.
local function toggle()
    local window = windowOf(hafen.session():current())
    if not (window and window.root:exists()) then
        hafen.log():write("simple-chat: no character on screen")
        return
    end
    window.root:visible(not window.root:visible())
end

hafen.console():on("simplechat", toggle)
hafen.client():options():keybindings():on("toggle", toggle)
