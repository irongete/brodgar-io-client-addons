-- Simple Chat -- the client's chat as a movable, resizable window, with the channels as tabs across the top.
--
-- The manifest runs the files in order into one environment; each adds its module under `SimpleChat`:
--   layout.lua      constants (this file)
--   clientchat.lua  hiding the client's own chat, keeping it hidden, giving it back
--   tabs.lua        one tab per channel, and the frame cut under the selected one
--   log.lua         the lines of the selected channel
--   window.lua      one window per login, on that login's HUD
--   main.lua        events, the console command and the hotkey

SimpleChat = {}
SimpleChat.windows = {} -- [session] = window record (window.lua)

-- The channel on screen in this window's login; nil once the login is gone or before its HUD is up.
function SimpleChat.selectedChannel(window)
    return window.session:exists() and window.session:chat():selected() or nil
end

local Layout = {}
SimpleChat.Layout = Layout

-- gfx/hud/wnd, the client's window box: 8 px corners, 7 px edge runs (design px).
Layout.FRAME_BOX = "gfx/hud/wnd"
Layout.CORNER = 8
Layout.RUN = 7
Layout.PAD = Layout.CORNER + 2 -- content keeps this far inside the frame

Layout.GAP = 2 -- between two tabs, and between two lines
Layout.TAB_HEIGHT = 28
Layout.TAB_DROP = 3 -- the strip's top margin: every tab starts on this row
Layout.TAB_LIFT = 1 -- air between an unselected tab and the frame
Layout.SEAT = 1 -- the selected tab overlaps the frame by this much: no world shows in the seam
Layout.STRIP = Layout.TAB_DROP + Layout.TAB_HEIGHT + Layout.TAB_LIFT -- the band above the panel
Layout.TAB_ON_HEIGHT = Layout.STRIP - Layout.TAB_DROP -- the selected tab reaches the frame's top edge
Layout.HOLE_HEIGHT = Layout.PAD -- the frame is cut this deep under the selected tab: past its top run
Layout.TAB_MAX_WIDTH = 110
Layout.TAB_MIN_WIDTH = 44
Layout.CLOSE_WIDTH = 14 -- the close zone at the right end of the selected private tab
Layout.CLOSE_GLYPH = "\195\151" -- x (multiplication sign)

Layout.SIZER = Layout.PAD -- the resize grip is the frame's own bottom-right corner
Layout.ENTRY_HEIGHT = 20 -- assumed until the entry's art answers, the tick after it is built
Layout.MIN_WIDTH = 240
Layout.MIN_HEIGHT = Layout.STRIP + 120
Layout.DEFAULT_WIDTH = 440
Layout.DEFAULT_HEIGHT = Layout.STRIP + 190
Layout.DEFAULT_X = 20
Layout.DEFAULT_Y = 20

-- tab.png / tab-on.png are gfx/hud/wnd's corners and runs at design scale. tab-on is sliced 8/8/8/1: its
-- bottom row carries the two side runs only, so the selected tab has no foot and runs down into the frame.
Layout.TAB_OFF_ASSET = "tab.png"
Layout.TAB_ON_ASSET = "tab-on.png"
Layout.TAB_OFF_SLICE = {8, 8, 8, 8}
Layout.TAB_ON_SLICE = {8, 8, 8, 1}
-- One RUN square each: the frame's top run turning up into the selected tab's side (no nine-slice corner has
-- the metal on three sides).
Layout.JOINT_LEFT_ASSET = "joint-l.png"
Layout.JOINT_RIGHT_ASSET = "joint-r.png"
-- SIZER square: three strokes across the frame's corner, as the client's own sizer, in {26, 34, 24, 200}.
Layout.SIZER_ASSET = "sizer.png"

Layout.FIELD = {43, 51, 44, 127} -- the panel and the selected tab: the action bars' translucent field
Layout.TAB_FILL = {14, 19, 15, 190} -- an unselected tab
Layout.TEXT = {206, 214, 200, 255}
Layout.DIM = {148, 158, 144, 255} -- an unselected tab's name
Layout.UNREAD = {235, 196, 96, 255} -- a tab with unread lines
Layout.ELLIPSIS = "\226\128\166"
