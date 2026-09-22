# HUD

Your character's health, stamina and energy drawn as three flat bars, each one placed, sized and coloured
on its own. With them on, the client's own three meters are hidden.

## Usage

1. Tick **Enable** in **Options ▸ AddOns ▸ HUD**. The three bars appear down the left of the screen and
   the client's own health, stamina and energy meters go away.
2. Hold **ALT** and drag a bar to move it. Each bar moves on its own, and every bar's outline turns yellow
   while ALT is down, so you can see what you are about to take hold of.
3. A click without ALT passes straight through a bar to whatever is under it.

Where you drop a bar is remembered, and so is every setting, across characters and restarts. Unticking
**Enable** hides the bars and gives the client's meters back, and so does disabling the addon.

## Options

**Options ▸ AddOns ▸ HUD**, per bar:

- **Width**, **Height**, **Border** — the bar's box and the line round it, in pixels. A border of `0`
  leaves the bar bare.
- **Reading** — on the health bar only, what it writes across itself:
  - **Percentage** — `87%`, and what every bar does.
  - **Percentage and amount** — `87% (35/40)`.
  - **Amount** — `35/40`.
  - **Nothing** — the bar and no text.
- **Font size** — how big that line is set, `6` to `32` pixels. A bar with less than three pixels of room
  over the size leaves the line off rather than clipping it.
- **Default colour** — ticked, the bar is painted the colour the client's own meter uses. This is how each
  bar starts, and while it is ticked the three sliders under it are greyed out.
- **R**, **G**, **B** — `0` to `255`. They paint the bar once **Default colour** is unticked.

## Notes

- Health is the only bar the server states an amount for, which is why it is the only one with a
  **Reading** setting. A server that stops stating it leaves the percentage standing.
- A bar shows every band the server publishes for it, so a bar the server splits shows the split.
- The extra bars a mount puts in the HUD are left alone: those stay the client's to draw.
- The bars are drawn over your windows as well as over the world, and they follow whichever character is
  on screen.
