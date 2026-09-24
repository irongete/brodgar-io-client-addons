# Extended Village Permissions

A village or realm has 255 permission groups, numbered 0 to 254, but the client only draws eight colour
squares to pick from. This addon puts a dropdown with every group beside those squares, so you can use
the whole range.

## Usage

1. Open your village or realm window as usual — the **Village** and **Realm** tabs, and a member's own
   panel.
2. Beside the row of eight colours there is a dropdown listing 0 to 254. Pick a number and the window
   sends it the way it sends one of its own.

Member and kin rows also carry the group number at their right edge, because every group above the eighth
is drawn in the same colour and the number is the only thing that tells them apart.

## Searching by group

The member list of the **Village** and **Realm** tabs searches as you type: click the list and type part of
a name. Type a group number instead, `12` say, and the list keeps the members of group 12 and nobody else.
Clear it with Backspace, or click outside the list.

- Only digits count as a group: `12` is group 12, while `b12` searches names as usual.
- The search needs a client that lets addons join a list's search. On an older one the rest of the addon
  works as before, and its log says the search cannot be filtered.

## Notes

- The dropdown sits under the colour row where there is space, and beside it where there is not.
- A claim's own permission window keeps the eight squares alone: a claim holds eight rows, and a higher
  group would be accepted and then dropped.
- The dropdown always shows what the row shows, so a group set elsewhere appears here too.
