# Trellis Builder

Point at a block pile, a string pile and a patch of ground, and press **Start**. The character fetches
what a trellis takes, walks there by a route it works out itself, and fills every tile of the patch with
as many trellises as the trellis's own footprint leaves room for.

## Usage

1. Type `:trellis` at the console to open the window.
2. Press **Block pile area** and click one corner of the ground your block piles stand on, then the
   opposite corner. A right-click cancels the pick. While a pick is running your clicks do not reach the
   game, so nothing is selected or walked to by accident.
3. Do the same with **String pile area**, over the piles holding the other material, and with
   **Trellis build area** for the patch to fill. Every whole tile the rectangle touches is built on.
4. Press **Start**. The line at the bottom of the window says what it is doing and how many it has built.
   **Stop** halts it after the step in progress.

The three areas are saved per account, so they survive a restart. `:trellis clear` forgets all three, and
`:trellis status` says what they are, what the piles turned out to hold and how the job is going.

## Notes

- It learns the materials from the piles themselves: it draws one item out, reads what arrived, and that
  is the material from then on. Nothing has to be named, and re-picking an area makes it learn afresh.
- It fills the patch from the far end back, always from the side the piles are on, so a finished row is
  never something it has to reach over or walk round.
- A spot the server refuses — the ground is not clear enough for a trellis there — is skipped, and the
  closing line says how many were.
- It never stands where a trellis goes: it walks to the tile beside the spot and lets the placement click
  take the last step.
- A building ghost left on the cursor is taken off for you, on **Stop** and before every trip to a pile.
- The job runs on the character it was started on. Tab away and it waits, saying so, rather than acting on
  somebody else.
- It stops when the pile runs dry, when the patch is full, or when what the character carries is not
  enough for one more trellis.
