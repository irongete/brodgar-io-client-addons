# WASD Movement

Walk with **W**, **A**, **S** and **D**. The keys go by the camera rather than by the way your character is
facing: **W** walks away from the camera, up the screen, **S** back down towards it, **A** and **D** off to
either side, and two of them together walk the diagonal between. Let go and the character stops.

## Bind the keys first

The four rows start unbound. Open **Options ▸ Game ▸ Keybindings ▸ WASD Movement** and give each one a key:

| Row | Key |
|---|---|
| Forward (W) | `W` |
| Left (A) | `A` |
| Back (S) | `S` |
| Right (D) | `D` |

Any four keys will do, and bare `W`, `A`, `S` and `D` are free in this client.

## Use

| You do | It does |
|---|---|
| hold **W** | walks away from the camera, up the screen |
| hold **S** | walks back towards the camera |
| hold **A** or **D** | walks ninety degrees off to that side of the screen |
| hold two, **W** + **D** and the other three pairs | walks the diagonal between them |
| hold **W** + **S**, or **A** + **D** | nothing: they cancel out |
| let go | stops the character |
| left-click the ground | cancels the walk, as it cancels anything else |

Typing never walks you: while a text field has the keyboard — chat, a marker name, a form — the keys write.

## Turning

There is no turn key: **you turn by moving the camera.** Drag the view round with a key still held and the
walk comes round with it, so **W** always means up the screen whatever your character faces. **A** and **D**
turn and walk rather than sidestep, and the body swings round to face where it is going.

## Notes

- Tab to another character and the keys drive that one; whatever the first was walking is stopped.
- A key held while the window loses focus is let go of, so alt-tab does not leave you walking.

## Permissions

- `player.move` — walks your character.
- `widget.send` — stops it, with the message the **Escape** key sends.
