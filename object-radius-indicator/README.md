# Object Radius Indicator

Lays a coloured circle on the ground under every object on its list, and the circle follows the object
as it moves. It starts out listing the hostile creatures, such as bears, wolves, boars, trolls and adders,
and you can add any other object by name.

## Usage

The circles are on as soon as the addon is loaded. There is no key: turn them on and off with
**Draw circles** in **Options ▸ AddOns ▸ Object Radius Indicator**.

To choose which objects get a circle, press **Objects...** on that page:

- Tick or untick an object to turn its circle on or off.
- **Edit** gives that object a look of its own. **Use general look** puts it back on the page's settings.
- **X** takes the object off the list. To put a built-in one back, add it again by name.
- To add one, type its resource name in the field at the bottom and press **Add** or Enter. The end of the
  name is enough, so `/fox` matches `gfx/kritter/fox/fox`.

## Options

**Options ▸ AddOns ▸ Object Radius Indicator**:

- **Draw circles**: turns every circle on or off.
- **Radius**: in world units from the object's centre to the rim. A tile is 11 units, so `110` is ten
  tiles.
- **Fill colour** and **Fill opacity**: the colour laid over the ground inside the circle. At `0` opacity
  only the rim is drawn.
- **Border colour** and **Border thickness**: the rim, always solid. Thickness is in hundredths of a
  world unit, so `30` is a thin line. To hide the rim, give it the fill's colour.
- **Draw through the world**: shows the whole circle even behind hills, walls and trees.

An object with a look of its own keeps it when you change these. The list, the ticks and every setting
are remembered.

## Notes

- The circle lies on the terrain and follows slopes.
- With more than one character logged in, circles are drawn only for the character on screen.
