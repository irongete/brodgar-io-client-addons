# Essentials

Three things the client can do for a character the moment it enters the world: turn toggles on, open the
inventory, and set the movement speed. There is no window — the rows are in **Options ▸ AddOns ▸
Essentials**, and everything is off until you turn it on.

## Options

**Options ▸ AddOns ▸ Essentials**:

- **Toggles at login** — Criminal Acts and Swimming, each with a box of its own. A toggle already on is
  left alone.
- **Open inventory on login** — opens the inventory window.
- **Set speed at login** — puts the character on Crawl, Walk, Run or Sprint. **None** leaves the speed as
  it is.

## Notes

- It waits a few seconds after the character enters the world, so the toggles can be read before they are
  pressed, and gives up on one that never arrives.
- A speed the character has not unlocked yet is left as it is.
- Pressing **Reload UI** does not re-run it for characters already in the world.
