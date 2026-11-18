# 13 — PPU background rendering

**Depends on:** 12

## Goal

Render the background into the frame buffer with the real fetch pipeline and scrolling, and dump frames to an image
file for inspection. Milestone M3.

## Context

On visible and pre-render scanlines, every 8 dots the PPU fetches: nametable byte, attribute byte, pattern low byte,
pattern high byte (2 dots each). Two 16-bit pattern shift registers and two attribute shift registers feed one pixel
per dot; fine X (`x`) selects the bit. Scroll updates on `v`:

- coarse X increment every 8 dots (dots 8, 16, …, 256 and 328, 336), wrapping into the next horizontal nametable;
- Y increment at dot 256 (fine Y, then coarse Y with the row-29 wrap into the next vertical nametable);
- copy horizontal bits `t → v` at dot 257;
- copy vertical bits `t → v` at dots 280–304 of the pre-render line.

Colour: a 2-bit pattern value of 0 is transparent and shows the universal background colour `$3F00`; otherwise
`palette = $3F00 + attribute * 4 + pattern`. PPUMASK can hide the leftmost 8 pixels and apply greyscale (`& $30`).

## Scope

In: the background pipeline above, writing palette indices to the frame buffer (contract from plan 01), greyscale and
left clipping; a debug PPM/PNG dumper with an NTSC palette table (`Ruby::Nes::Debug::FrameDump`, not on the hot path).

Out: sprites (plan 14), colour emphasis (applied by frontends later), the formal frontend interface (plan 16).

## Open decisions

- Accuracy vs speed: a per-dot pipeline (accurate, mid-scanline effects work) vs per-scanline tile rendering (much
  faster in Ruby, breaks mid-scanline tricks). Recommendation: per-dot now, correctness first; plan 25 may add a fast
  path when no mid-scanline write happened.
- Which RGB palette to ship (the NES has no canonical RGB). Options from the "PPU palettes" page; pick one whose
  licence allows redistribution, record its source in the file header.

## Tasks

- [ ] Specify and test the scroll increments (each wrap case) and the `t → v` copies.
- [ ] Specify and test pixel selection: fine X, attribute quadrant selection, transparent pixel, left clipping,
      greyscale.
- [ ] Frame dumper (`rake debug:frame[rom,frame_number,out]`).
- [ ] Render a background-only screen of a test ROM (e.g. nestest's menu, or a blargg result screen) and inspect it.

## Acceptance criteria

- [ ] A dumped frame of nestest (run from its reset vector) shows its text menu correctly.
- [ ] A golden digest of that frame is stored and checked by a context declaring `test_rom: 'other/nestest.nes'`,
      in the spec tree of the entry point that renders the frame (regression guard after human inspection).
- [ ] Scrolling leaves: coarse X wrap switches horizontal nametable, coarse Y wraps at 29 (and at 31 without
      switching), fine Y carry.
- [ ] 100% branch coverage on the background pipeline; rubocop clean.

## References

- PPU rendering — https://www.nesdev.org/wiki/PPU_rendering
- PPU scrolling — https://www.nesdev.org/wiki/PPU_scrolling
- PPU pattern tables — https://www.nesdev.org/wiki/PPU_pattern_tables
- PPU attribute tables — https://www.nesdev.org/wiki/PPU_attribute_tables
- PPU palettes — https://www.nesdev.org/wiki/PPU_palettes
- PPU frame timing diagram — https://www.nesdev.org/w/images/default/4/4f/Ppu.svg
