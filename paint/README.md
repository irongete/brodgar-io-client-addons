# Paint

Draw on the ground with the mouse. A stroke lies flat on the terrain, follows its slopes and ridges, and is
hidden by whatever stands on it, your own character included. Six colours, an eraser, a width slider and a
Clear button.

What you draw is on your own screen only: nothing is sent to the server and nobody else sees it. A drawing
lasts until you reload the addons, log out or disable the addon.

## Use

| You do | It does |
|---|---|
| press **Paint** in the action menu | opens the tool window, or closes it |
| click a colour | picks that pencil; click it again to put it down |
| click the grey cell with the slash | picks the eraser |
| drag on the ground with a pencil picked | lays a stroke where the pointer goes |
| drag on the ground with the eraser picked | rubs out what it passes over |
| right-click on the ground | puts the picked tool down |
| move the **Width** slider | sets how wide a stroke is; under the eraser it reads **Rub** and sets how much the eraser takes at a pass |
| **Clear** | takes the whole drawing up |
| close the window | puts the picked tool down |

The **Paint** button sits on the root screen of the action menu, so it can be dragged onto an action bar like
any other action.

While a pencil or the eraser is picked, the map is the addon's: a left click draws instead of walking, a right
click puts the tool down instead of doing what it usually does, and the cursor changes to say so. With no tool
picked the map behaves as usual.

Long strokes are drawn in several parts; the colours are opaque so the parts read as one shape. The eraser
removes whole pieces of a stroke, so a narrow setting rubs out finer detail than a wide one.

## Permissions

None. The addon draws on your own screen and sends nothing to the server.
