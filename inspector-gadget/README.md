# Inspector Gadget

A magnifying glass in the action menu. Turn it on and a tooltip beside the pointer says everything the
client knows about whatever you are hovering — an object, or the ground itself.

## Usage

1. Open the action menu and press **Inspector Gadget**. The pointer becomes the game's own magnifying
   glass. The entry is an ordinary action, so it drags onto an action bar like any other.
2. **Hover anything.** The tooltip appears beside the pointer and follows it, describing the object under
   it, or the ground where there is no object.
3. **Left-click an object** to run the game's own Inspect on it. The answer arrives where the game always
   puts it.
4. **Right-click the ground**, or press the menu entry again, to put the glass away.

## What the tooltip says

About an **object**: its resource name and the server's id for it, where it stands, which tile it is in,
how far it is from your character, which way it faces, what integrity it has left, whether it is still or
moving and how fast, whether it is a player and the kin standing there, its minimap icon and anything it
is saying. A tree, a crop or a gate also shows the raw state the server sent it with; a player or an
animal shows the poses it is playing instead, and both show whatever the game is drawing at them — a
fire's flame, a fight's effects.

About the **ground**: the tileset it is drawn from, the point and the tile it falls in, the terrain
height, and the map grid it belongs to.

Everything is read live, on every frame, so a boar that starts running says so while it runs. A boulder
answers three of those questions and a player a dozen; a row with no answer is not shown.

## Notes

- The glass takes two gestures and leaves the rest alone: a left-click on an **object** becomes the
  Inspect, and a right-click on the **ground** puts the glass away. Everything else goes through — a
  left-click on the ground still walks you there, and a right-click on an object still opens its ring.
- The object described is exactly the object a click would have reached: the client is asked, so there is
  nothing to approximate and nothing to tune.
- Over a window, or the sky, the tooltip puts itself away. With the glass down the addon costs a menu
  entry and nothing else.
