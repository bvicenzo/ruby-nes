# 13 — PPU background rendering

**Depends on:** 12

**Status:** done (2026-11-19)

## Goal

Render the background into the frame buffer with the real fetch pipeline and scrolling, and dump frames to an image
file for inspection. Milestone M3.

## Context

Facts below were checked against the NESdev pages in References on 2026-11-19.

[PPU rendering](https://www.nesdev.org/wiki/PPU_rendering): on visible and pre-render scanlines, "Each memory access
takes 2 PPU cycles to complete, and 4 must be performed per tile": nametable byte, attribute table byte, pattern table
tile low, pattern table tile high ("8 bytes above pattern table tile low address"). The data goes into latches "and
then fed to the appropriate shift registers when it's time to do so (every 8 cycles)"; "The shifters are reloaded
during ticks 9, 17, 25, ..., 257". Dots 321-336 fetch "the first two tiles for the _next_ scanline"; dots 337-340
fetch two nametable bytes whose "purpose for this is unknown" (only MMC5 uses them). Pattern data goes "into the high 8
bits of two 16-bit shift registers" (on the page's diagram; emulators load the low byte and read from the top, the
same pixel order), attributes "into two 1-bit latches that feed 8-bit shift registers". The page's frame timing
diagram ([Ppu.svg](https://www.nesdev.org/w/images/default/4/4f/Ppu.svg)) marks the shifter reloads after each of
the two tiles of 321-336 too, which puts them at dots 329 and 337. Each dot "a 4-bit pixel is
selected by the fine x register" from the shifters, "which are then shifted". Dot 0 "is an idle cycle". "the first
pixel is output during cycle 4" because of pipelining; the page gives no dot-to-x mapping (decision 5).

[PPU scrolling](https://www.nesdev.org/wiki/PPU_scrolling), each step only "If rendering is enabled" (PPUMASK bit 3 or
4):

- coarse X increment at dots 328 and 336, "and will continue through the next scanline at 8, 16, 24... 240, 248,
  256": "if ((v & 0x001F) == 31) ... v &= ~0x001F ... v ^= 0x0400 // switch horizontal nametable ... else v += 1";
- Y increment at dot 256: fine Y < 7 increments; otherwise fine Y = 0 and coarse Y increments, "if (y == 29) y = 0
  ... v ^= 0x0800 // switch vertical nametable", "else if (y == 31) y = 0 // coarse Y = 0, nametable not switched";
- dot 257: "v: ....A.. ...BCDEF <- t: ....A.. ...BCDEF" (horizontal bits);
- dots 280-304 of the pre-render line: "v: GHIA.BC DEF..... <- t: GHIA.BC DEF....." (vertical bits);
- fetch addresses: "tile address = 0x2000 | (v & 0x0FFF)", "attribute address = 0x23C0 | (v & 0x0C00) | ((v >> 4) &
  0x38) | ((v >> 2) & 0x07)";
- "During rendering (on the pre-render line and the visible lines 0-239, provided either background or sprite
  rendering is enabled)", a `$2007` access updates v by "triggering a coarse X increment and a Y increment
  simultaneously (with normal wrapping behavior)", "not affected by the status of the increment bit".

[PPU pattern tables](https://www.nesdev.org/wiki/PPU_pattern_tables): address `0HNNNN NNNNPyyy` (H half, N tile
number, P bit plane, y fine Y); "Each bit in the first plane controls bit 0 of a pixel's color index; the corresponding
bit in the second plane controls bit 1"; the page's worked example has bit 7 as the leftmost pixel. PPUCTRL bit 4:
"Background pattern table address (0: $0000; 1: $1000)" ([PPU registers](https://www.nesdev.org/wiki/PPU_registers)).

[PPU attribute tables](https://www.nesdev.org/wiki/PPU_attribute_tables): "value = (bottomright << 6) | (bottomleft <<
4) | (topright << 2) | (topleft << 0)", each quadrant 2×2 tiles. The quadrant is picked by coarse X bit 1 (left/right)
and coarse Y bit 1 (top/bottom): a derivation from the attribute address layout, not page text.

Colour ([PPU palettes](https://www.nesdev.org/wiki/PPU_palettes), [PPU registers](https://www.nesdev.org/wiki/PPU_registers)):
a 5-bit palette RAM index from "Background/Sprite select", "Palette number from attributes" and "Pixel value from tile
pattern data"; pixel value 0 is transparent and shows "The backdrop color ($3F00)". PPUMASK bit 1 "Show background in
leftmost 8 pixels of screen, 0: Hide" ("making them transparent and thus drawing the backdrop color there"), bit 3
"Enable background rendering", bit 0 greyscale, "bitwise ANDing the color with $30". With rendering disabled ("forced
blank") the PPU draws the backdrop, but "if the current VRAM address in v points into palette RAM ($3F00-$3FFF), then
the color at that address will be drawn, instead" (Backdrop override). The override looks v up through the 14-bit
PPU bus, ignoring v's top bit as a `$2007` access does ("The highest bit is unused" for that access, PPU scrolling):
a derivation, the page does not say it for the backdrop.

## Scope

In: the background pipeline above, writing palette indices to the frame buffer (contract from plan 01); greyscale,
left clipping and the backdrop override; PPUDATA's v update during rendering; a debug PPM dumper with an NTSC palette
table (`Ruby::Nes::Debug::FrameDump`, not on the hot path) and `rake debug:frame`.

Out: sprites (plan 14), colour emphasis (applied by frontends later), the formal frontend interface and PNG (plan 16),
the rendering toggle delay (decision 4), the fetches with no observable effect (decision 6).

From plan 12: `Ppu::FrameTiming` advances one dot at a time (scanline, dot, frame number, odd-frame skip) and
`Ppu#catch_up(cpu_cycle)` runs dots up to the CPU's time, also before every PPU register access (plan 12, decision 1),
so mid-scanline register writes land on the right dot. The per-dot pipeline hangs off that dot step.

## Decisions

Settled with the user on 2026-11-19.

1. **Per-dot pipeline** (fetches every 2 dots, shift registers, v updates on the dots NESdev gives). Reason:
   correctness first; mid-scanline writes (SMB3's status bar split) work. Plan 25 may add a measured fast path.
2. **RGB palette: NESdev's `2C02G_U_wiki.pal`** ([File:2C02G_U_wiki.pal](https://www.nesdev.org/wiki/File:2C02G_U_wiki.pal),
   "A palette generated by Pally v0.23.0", generator MIT-0; the wiki's
   [General disclaimer](https://www.nesdev.org/wiki/Nesdev_wiki:General_disclaimer): "Any information posted on this
   wiki is considered public domain"), embedded as a constant with its source in the file header. Reason: an NTSC
   2C02 palette from the reference site, redistributable. The wiki refuses scripted downloads, so the bytes come from
   the generator's copy of the same file ([pally](https://github.com/Gumball2415/pally), `docs/NESDev`, MIT-0): 1536
   bytes, 64 colours for each of the 8 emphasis combinations; the first 64 (no emphasis) are embedded.
3. **The dumper writes PPM (P6)**; the PNG encoder stays in plan 16. Reason: a few lines, no compression; plan 16
   owns image encoding for frontends.
4. **Extra scope:** PPUDATA's coarse X + Y update during rendering and the backdrop override are in. The 3-4 dot delay
   of a rendering toggle is out: the source is vague ("approximately"); its Known gap moves to a later PPU pass and
   `ppu_vbl_nmi/10` keeps failing as recorded.
5. **The pixel of dot 1-256 of a visible scanline goes to x = dot − 1.** A convention: the page says the first pixel
   is output at cycle 4 through pipelining but maps no dot to x; it only matters for sprite 0 hit timing (plan 14).
6. **Fetches with no observable effect are not made**: the garbage nametable fetches of dots 257-320 and the two of
   337-340 (only MMC5 counts them). The sprite pattern fetches of 257-320 (MMC3's A12) belong to plans 14 and 21.
7. **`Ppu::DataPort` asks `FrameTiming#rendering_in_progress?` on each `$2007` access.** Reason: the frame timing
   already knows the scanline and the rendering flags; pushing "rendering started/stopped" events would need four of
   them per frame for a rare access.
8. **The planned `Picture` is split into `Picture` (frame buffer, palette lookup, greyscale, forced blank) and
   `BackgroundVisibility` (background disabled, left clipping, transparent pixel).** Reason: greyscale crossed every
   branch of the visibility tree; plan 14 composes sprites through the same two pieces.
9. **The renderer is split into `BackgroundSchedule` (which steps a dot makes, constant tables per kind of scanline)
   and `BackgroundRenderer` (runs them).** Reason: the timing is data rows checked one dot at a time; the renderer
   then has one leaf per step. Within a dot the steps run reload, pixel, shift, fetches, v updates, so a reload feeds
   the pixel of its own dot. The fetch of a 2-dot access happens on its first dot. The rendering flag is told by the
   `Ppu` to both `FrameTiming` (odd-frame skip, PPUDATA) and `BackgroundSchedule`; only specs that build them with
   keywords can set them apart.
10. **The nestest golden digest runs in the default suite**, not tagged `slow: true`: it takes about 1.1 s (the tag is
    for runs over ~2 s). The frame is the 10th from reset; its first pixels of row 0 belong to the 11th, which
    `run_frame` has started (docs/architecture.md, Frame buffer contract; plan 16 decides a complete frame).

## Tasks

- [x] `Ppu::ScrollRegisters`: coarse X increment, Y increment (each wrap case), the horizontal and vertical `t → v`
      copies, and PPUDATA's update during rendering.
- [x] `Ppu::DataPort`: the rendering update of v instead of +1/+32 while rendering is in progress.
- [x] `Ppu::BackgroundFetcher`: nametable, attribute (reduced to the quadrant's 2 bits), pattern low and high fetches
      from v and PPUCTRL bit 4.
- [x] `Ppu::BackgroundShifters`: reload, shift, the 4-bit pixel selected by fine X.
- [x] `Ppu::Picture`: the preallocated frame buffer, the palette lookup, greyscale, forced blank with the backdrop
      override (decision 8).
- [x] `Ppu::BackgroundVisibility`: the palette entry of a background pixel (disabled, left clipping, transparent).
- [x] `Ppu::BackgroundSchedule`: the steps of each dot of visible, pre-render and idle scanlines, with rendering on or
      off, from constant tables (decision 9).
- [x] `Ppu::BackgroundRenderer`: runs a dot's steps on the fetcher, shifters, scroll registers, visibility and picture;
      passes the PPUCTRL and PPUMASK settings to their parts.
- [x] `Ppu` wiring: the renderer runs per dot in `catch_up`; PPUCTRL bit 4 and PPUMASK bits 0, 1, 3, 4 reach it;
      `Ppu#frame_buffer`.
- [x] `Debug::FrameDump` (palette table, PPM) and `rake debug:frame[rom,frame_count,output]`.
- [x] Render nestest's menu (from its reset vector), inspect it, and store its golden digest.
- [x] `docs/architecture.md` (layout, frame buffer, Known gaps, decisions), `docs/GLOSSARY.md`.

## Acceptance criteria

- [x] A dumped frame of nestest (run from its reset vector) shows its text menu correctly.
- [x] A golden digest of that frame is stored and checked by a context declaring `test_rom: 'other/nestest.nes'`,
      in the spec tree of `Console#run_frame` (regression guard after human inspection).
- [x] Scrolling leaves: coarse X wrap switches horizontal nametable, coarse Y wraps at 29 (and at 31 without
      switching), fine Y carry, the horizontal and vertical copies.
- [x] Pixel leaves: fine X, attribute quadrant selection, transparent pixel, left clipping, greyscale, backdrop
      override.
- [x] A PPUDATA access during rendering increments coarse X and Y instead of adding 1 or 32.
- [x] `rake debug:frame[…]` writes a PPM.
- [x] 100% branch coverage on the background pipeline; rubocop clean; `SLOW=1 bundle exec rake` green.

## What was done

- `Ppu::ScrollRegisters`: coarse X and Y increments with their wraps, the horizontal and vertical `t → v` copies.
- `Ppu::FrameTiming#rendering_in_progress?` and `Ppu::DataPort`: a `$2007` access during rendering increments coarse
  X and Y instead of adding 1 or 32.
- The background pipeline: `BackgroundFetcher` (nametable, attribute quadrant, pattern planes), `BackgroundShifters`
  (16-bit registers, pixel under fine X), `BackgroundVisibility` (disabled, left clipping, transparent), `Picture`
  (frame buffer, palette lookup, greyscale, forced blank with the backdrop override), `BackgroundSchedule` (step
  flags per dot from constant tables) and `BackgroundRenderer` (runs them), driven per dot by `Ppu#catch_up`; PPUCTRL
  bit 4 and PPUMASK bits 0, 1, 3 and 4 reach it; `Ppu#frame_buffer`.
- `Debug::FrameDump` (PPM with the 64 colours of `2C02G_U_wiki.pal`) and `rake debug:frame[rom,frame_count,output]`.
- nestest's menu renders correctly from its reset vector (10th frame, inspected); its SHA-256 is checked in the spec
  of `Console#run_frame`. Milestone M3 (first image) reached.
- Independent review: no correctness bugs; shifters masked to 16 bits, a reload leaf with a queued tile, shared PPU
  bus and palette constants, sources added to Context, the frame buffer caveat documented for plan 16.

## References

- PPU rendering — https://www.nesdev.org/wiki/PPU_rendering
- PPU scrolling — https://www.nesdev.org/wiki/PPU_scrolling
- PPU pattern tables — https://www.nesdev.org/wiki/PPU_pattern_tables
- PPU attribute tables — https://www.nesdev.org/wiki/PPU_attribute_tables
- PPU palettes — https://www.nesdev.org/wiki/PPU_palettes
- PPU registers — https://www.nesdev.org/wiki/PPU_registers
- 2C02G_U_wiki.pal — https://www.nesdev.org/wiki/File:2C02G_U_wiki.pal
- PPU frame timing diagram — https://www.nesdev.org/w/images/default/4/4f/Ppu.svg
- PPM format — https://netpbm.sourceforge.net/doc/ppm.html
