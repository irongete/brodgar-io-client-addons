# Paint

Draw on the ground with the mouse. A stroke lies flat on the terrain, follows its slopes and ridges, and
is hidden by whatever stands on it, your own character included. Six colours, an eraser, a width slider
and a Clear button.

## Usage

1. Press **Paint** in the action menu to open the tool window, and again to close it. The entry sits on
   the root screen of the menu, so it drags onto an action bar like any other action.
2. Click a colour to pick that pencil, or the grey cell with the slash to pick the eraser. Clicking the
   same cell again puts the tool down, and so does a right-click on the ground or closing the window.
3. **Drag on the ground** to lay a stroke where the pointer goes, or to rub out what it passes over with
   the eraser picked.
4. The **Width** slider sets how wide a stroke is. Under the eraser it reads **Rub** and sets how much it
   takes at a pass. **Clear** takes the whole drawing up.

While a tool is picked the map is the addon's: a left click draws instead of walking, a right click puts
the tool down, and the cursor changes to say so. With no tool picked the map behaves as usual.

## Notes

- What you draw is on your own screen only. Nothing is sent to the server and nobody else sees it.
- A drawing lasts until you reload the addons, log out or disable the addon.
- Long strokes are drawn in several parts, and the colours are opaque so the parts read as one shape.
- The eraser removes whole pieces of a stroke, so a narrow setting rubs out finer detail than a wide one.
