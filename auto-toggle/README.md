# Auto Toggle

Turns on the toggles you pick, such as Criminal Acts and Swimming, every time a character logs in.

## Usage

1. Open **Options ▸ AddOns ▸ Auto Toggle**. The page shows a grid of your character's toggle icons, the
   same ones you find under **Adventure ▸ Toggle**.
2. Click an icon to pick it. Picked toggles are drawn in full colour, the rest are drawn dark.
3. From then on, every character that enters the world gets those toggles turned on.

Your picks are kept between sessions and shared by every account and character on this client.

## Notes

- The grid lists exactly the toggles your character has. Log in once so the page can read them.
- A toggle that is already on is left alone.
- It waits a few seconds after you enter the world before it touches anything, and gives up on a toggle
  that never appears.
- It never writes to the chat or the console.
- Pressing **Reload UI** does not re-run it for characters already in the world.

## Permissions

It asks for `menugrid.use`, which lets it press an entry in your action menu. The client shows you the
request the first time you enable the addon; accept it and press **Reload UI**.
