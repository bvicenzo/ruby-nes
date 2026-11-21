# 27 — Horizontal edge crop

**Depends on:** 18

## Goal

A display option of the windowed frontend that hides the picture's left and right edges, where games leave the
backdrop strip of PPUMASK's hidden left column or the artifacts of horizontal scrolling. It is a choice about what the
window shows, never about what the PPU draws: emulation and the frame buffer stay unchanged.

## Context

Found while playing Super Mario Bros. 3 at the end of plan 21 (2026-11-21): during play the game writes PPUMASK `$18`
every frame. That turns on the background and the sprites and leaves bits 1 and 2 at 0, so the leftmost 8 columns
show the backdrop colour from the top of the screen to the bottom. In world 1-1 that is a sky-blue strip, beside the
black status bar too. The PPU is right to draw it. A headless run of 100 frames of 1-1 found all 192 000 pixels of
columns 0-7 in the backdrop colour.

- PPUMASK ([PPU registers](https://www.nesdev.org/wiki/PPU_registers)): bit 1 "1: Show background in leftmost 8
  pixels of screen, 0: Hide", bit 2 the same for sprites. Hidden pixels are "transparent and thus drawing the backdrop
  color there". For backgrounds this "can eliminate tile artifacts and reduce attribute artifacts when scrolling
  horizontally". The page warns: "the backdrop color may not match the color used by the art for the background, so
  disabling the left column may be more distracting than minor artifacts".
- On a TV ([Overscan](https://www.nesdev.org/wiki/Overscan)), the PPU "puts signal in 256 of these and a border at the
  left and right sides". "The color of this border is the same as the backdrop color". A scanline is 280 pixels long
  in total. So on a TV, the hidden left column runs into a border of the same colour instead of ending at the edge of
  a window.
- How far TVs and emulators crop sideways: Nintendo's guidelines "reserved 24 lines at the top and bottom and 16 pixels
  at the left and right as potential overscan". PocketNES "hides 8 pixels of overscan on the left and right, 16 on the
  top, and 11 on the bottom".
- Plan 18 already has a vertical crop: `--crop-overscan` shows lines 8 to 231 (plan 18, decision 4). That is
  `Frontends::Viewport`'s `source` rectangle (`CROPPED_FRAME`), drawn by `Frontends::Raylib#place_texture` through
  `DrawTexturePro`. A horizontal crop is another source rectangle, with no cost per frame.

## Scope

In:

- A command-line option, and the matching `Frontends::Viewport` input, that hides columns at the left and right edges.
  It combines with `--scale`, `--aspect` and `--crop-overscan`.
- The window's size follows the shown width, as it already does for the shown height.

Out:

- Any change to the PPU or the frame buffer. Headless screenshots and digests keep all 256 × 240 pixels.
- Cropping chosen per game, or detected from PPUMASK.

## Open decisions

1. **Which columns.**
   - (a) 8 on each side, as PocketNES does, so the picture stays centred.
   - (b) Only the left 8, which hides exactly PPUMASK's column, at the cost of an off-centre picture.
   - (c) 16 on each side, Nintendo's potential overscan.
   - Recommendation: (a).
2. **Option shape.**
   - (a) A new `--crop-sides` flag, independent of `--crop-overscan`.
   - (b) `--crop-overscan` crops both directions.
   - (c) `--crop-overscan=lines|sides|all`.
   - Recommendation: (a). The existing flag keeps its documented meaning, and the two crops answer different
     complaints.
3. **Crop or border.**
   - (a) Crop: the shown picture is narrower.
   - (b) TV border: draw a margin in the backdrop colour around the picture, so the strip runs into it as on a TV.
     This needs the backdrop colour of every frame, which is palette RAM `$3F00` and is not in the frame buffer
     contract today.
   - Recommendation: (a) in this plan, (b) in the backlog.
4. **Default.**
   - (a) Off: all 256 columns, matching plan 18's "all 240 lines by default".
   - (b) On.
   - Recommendation: (a).
5. **Config file.** Should the crop also be a setting in the config file (`keys:` is its only section today), or only
   an option on the command line? Recommendation: only the command line, as with `--crop-overscan`.

## Tasks

- [ ] Settle the open decisions and record them here.
- [ ] Specify and test `Frontends::Viewport` with the side crop: the source rectangle and the window size, alone and
      combined with the vertical crop, the scale and the 8:7 aspect.
- [ ] Specify and test the command-line option (`CommandLine::Options`) and its wiring into the viewport.
- [ ] Update `docs/architecture.md` (frontend section and command line) and the `--help` text.
- [ ] Play SMB3 with the option and check that the strip is gone and the status bar is whole (the user, in the window).

## Acceptance criteria

- [ ] With the option, the window shows neither the left strip of SMB3's world 1-1 nor the column on the opposite
      side. Without it, the window is unchanged.
- [ ] Headless frames, screenshots and digests are unchanged.
- [ ] 100% branch coverage on the units touched; rubocop clean; `bundle exec rake` green.

## References

- PPU registers, PPUMASK (the hidden left column) — https://www.nesdev.org/wiki/PPU_registers
- Overscan (the border, safe areas, PocketNES's crop) — https://www.nesdev.org/wiki/Overscan
- Plan 18, decision 4 (square pixels, all 240 lines by default, `--crop-overscan`).
