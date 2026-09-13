# Auto FlowerMenu

**Picks a petal off the radial menu for you, the instant the ring opens.** Which petal is yours to say:
the addon keeps a list of captions, and when a ring goes up it walks that list from the top and picks the
first entry the ring offers. A ring it picks from is never painted at all; one that offers nothing on the
list is left exactly as it was, for you to decide.

The list starts **empty**. Nothing is picked until you add something.

## The list

**Options ▸ AddOns ▸ Auto FlowerMenu.** Type a caption — the word the ring paints, `Pick`, `Chop`,
`Harvest` — and press **Add** or Enter. Each entry is a row:

| Button | Does |
|---|---|
| **Up** | moves the entry one place up the list |
| **Down** | moves it one place down |
| **X** | takes it off the list |

**The order is the priority.** With `Harvest` above `Pick`, a ring offering both is harvested; a ring
offering only `Pick` is picked. A caption is matched whole and without regard to case, so `pick` and
`Pick` are the same entry, and a blank or a repeat is not added.

The list is saved for the **account**, so every character picks from the same one, and it holds across
reloads and restarts.

## What it asks for

One permission, `flowermenu.select` — *pick a petal off the radial menu* — which is the whole of what it
does. It starts disabled for that: tick it in the AddOns panel, accept the key, and **Reload UI**.
