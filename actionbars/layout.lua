-- Actionbars -- one bar per page of the server's 144-slot belt, twelve buttons each, on the character's HUD.
--
-- The manifest runs the files in order into one environment; each adds its module under `Actionbars`:
--   layout.lua     constants and geometry (this file)
--   config.lua     one character's bars: on or off, flat or upright, how many buttons, where -- saved per character
--   options.lua    the twelve rows (mode and button count) on Options > AddOns > Actionbars, and the page
--   slots.lua      bar button -> belt slot, and pressing one
--   hotkeys.lua    "Actionbar<N> slot <I>" keybindings and the corner labels
--   bars.lua       the widgets of one bar, one copy per login
--   sync.lua       client belt hide/restore, sync with the options, Reset
--   main.lua       events and the label timer

Actionbars = {}

local Layout = {}
Actionbars.Layout = Layout

Layout.SLOTS_PER_BAR = 12 -- one page of the belt
Layout.MAX_BARS = 12 -- 144 / 12: a thirteenth bar would have no slots of its own
Layout.MAIN_BAR = 1 -- follows the client's current page, stands in for the client's bar, never off

Layout.SQUARE = 34 -- the client's inventory square, design px
Layout.ICON = 32 -- the square less its one-pixel ring
Layout.GAP = 2 -- between squares, as the F-key belt spaces them
Layout.PITCH = Layout.SQUARE + Layout.GAP

-- Length of a run of `buttonCount` squares, the gutters between them included and none after the last.
function Layout.barLength(buttonCount)
    return (buttonCount * Layout.PITCH) - Layout.GAP
end

Layout.DEFAULT_X = 200 -- a new bar while the HUD has no size to centre it on
Layout.DEFAULT_Y = 120
Layout.STACK_GAP = 6 -- between two bars of Reset's stack

-- The frame is the client's own window box, declared with widget:stock so any theme rule overrides it per
-- property. Its edge run is 7 design px (28 px at scale 4); the padding adds a 2 px margin around the buttons.
Layout.FRAME_BOX = "gfx/hud/wnd"
Layout.FRAME_EDGE = 7
Layout.PADDING = Layout.FRAME_EDGE + 2

-- haven.Inventory builds its square in code, so there is no resource to draw it by: these are its colours.
Layout.SLOT_FILL = {36, 52, 38, 125}
Layout.SLOT_EDGE = {20, 28, 21, 167}
Layout.LABEL_COLOR = {156, 180, 158, 255} -- the tone the belt prints "F1" in
Layout.COOLDOWN_COLOR = {255, 255, 255, 64} -- the recharge pie, as the action menu draws it
-- ISBox.bgcol, the flat field under a framed box. Not the window's tiled backdrop: `g` has no tiling verb,
-- and a 146 px texture stretched over a 430 px bar smears.
Layout.BAR_BACKGROUND = {43, 51, 44, 127}

-- Flat and upright are the same squares with the axes swapped. The swap happens in these three functions
-- only; nothing else knows which way a bar stands. A bar shows its first `buttonCount` slots (1..12, an
-- option per bar); the rest of its page stays on the server, reachable by hotkey.

-- Outer box of a bar showing `buttonCount` buttons.
function Layout.barBox(upright, buttonCount)
    local inset = Layout.PADDING * 2
    local length = Layout.barLength(buttonCount)
    if upright then
        return Layout.SQUARE + inset, length + inset
    end
    return length + inset, Layout.SQUARE + inset
end

-- Top-left of button `slotIndex`, in bar coordinates.
function Layout.slotOrigin(upright, slotIndex)
    local offset = (slotIndex - 1) * Layout.PITCH
    if upright then
        return Layout.PADDING, Layout.PADDING + offset
    end
    return Layout.PADDING + offset, Layout.PADDING
end

-- The button under a point in bar coordinates, or nil on the frame, the margin, a gutter or past the last
-- button shown. The one hit test behind pressing, dropping and the tooltip.
function Layout.slotAt(upright, buttonCount, x, y)
    local along, across
    if upright then
        along, across = y - Layout.PADDING, x - Layout.PADDING
    else
        along, across = x - Layout.PADDING, y - Layout.PADDING
    end
    if across < 0 or across >= Layout.SQUARE or along < 0 then
        return nil
    end
    local slotIndex = math.floor(along / Layout.PITCH) + 1
    if slotIndex > buttonCount then
        return nil
    end
    if (along - ((slotIndex - 1) * Layout.PITCH)) >= Layout.SQUARE then
        return nil -- the gutter between two squares
    end
    return slotIndex
end
