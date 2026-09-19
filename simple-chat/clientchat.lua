-- The client's own ChatUI: hidden while a window stands in for it, given back on Disable.
--
-- The client reopens its chat past the hide: Ctrl+C (`chat-toggle`) and the belt's Chat button call
-- chat.sshow(true) directly, and the client's toggle seam covers only its Windows, which the chat is not.
-- keepAway hides it again every tick, before the frame is drawn; hiding also drops the focus the key moved
-- into it. With Ctrl+C assigned to this addon's `toggle` hotkey the press never reaches the client at all.

local ClientChat = {}
SimpleChat.ClientChat = ClientChat

-- Taken whatever it was showing: a chat collapsed before the addon ran has no owner otherwise, and Ctrl+C
-- would bring it back. `chatWasShown` is what giveBack puts back.
function ClientChat.take(window)
    local chat = window.session:exists() and window.session:ui():match("@ChatUI")
    if not chat or window.hiddenChat then
        return
    end
    local wasShown = chat:visible()
    local ok, failure = pcall(function() chat:visible(false) end)
    if ok then
        window.hiddenChat, window.chatWasShown = chat, wasShown
    else
        hafen.log():write(failure)
    end
end

function ClientChat.keepAway(window)
    local chat = window.hiddenChat
    if chat and chat:exists() and chat:visible() then
        pcall(function() chat:visible(false) end)
    end
end

-- Teardown leaves a bare hide hidden, so a chat found shown is shown again here; one found collapsed stays so.
function ClientChat.giveBack(window)
    local chat = window.hiddenChat
    if chat and chat:exists() and window.chatWasShown then
        pcall(function() chat:visible(true) end)
    end
    window.hiddenChat = nil
end

-- Closes a private conversation as the client's own X does: `close` sent from the channel's widget (needs
-- widget.send). session:chat():list() and the ChatUI's children share one order, so the k-th private channel
-- is the k-th @PrivChat.
function ClientChat.closePrivate(window, channel)
    local rank = 0
    for _, other in ipairs(window.session:chat():list()) do
        if other:kind() == "chat.private" then
            rank = rank + 1
        end
        if other == channel then
            local ok, failure = pcall(function()
                local widget = window.session:ui():match("@ChatUI"):matchAll("@PrivChat")[rank]
                if widget then
                    widget:send("close")
                end
            end)
            if not ok then
                hafen.log():write(failure)
            end
            return
        end
    end
end

-- The belt's "Chat (Ctrl+C)" button: its press is cancelled and toggles this window instead.
function ClientChat.hookBeltButton(window)
    local ok, button = pcall(function() return window.hud:match("@NKeyBelt @IButton") end)
    if not (ok and button) then
        return
    end
    window.beltSubscription = button:on("Pressed", function(pressEvent)
        pressEvent:preventDefault()
        window.root:visible(not window.root:visible())
    end)
end
