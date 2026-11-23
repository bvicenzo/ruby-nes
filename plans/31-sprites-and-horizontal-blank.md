# 31 — Sprites and the horizontal blank

**Depends on:** 30

## Goal

Cut the sprite work and the per-dot path of dots 257-340 without changing a single pixel or fetch. The frame and audio
digests of `rake bench:frames` must stay those of the last kept step.

## Context

After plan 30, a Super Mario Bros. 3 frame takes about 20.7 ms under YJIT, and the sprite steps about 14% of it, about
2.9 ms (`docs/benchmarks.md`, Findings, plan 30). The sprite side of each pixel's composition is counted in the pixel
share: `Ppu::PixelComposer#draw_tile` composes a whole tile's 8 pixels with the sprite line. Every visible pixel reads
the sprite line, even on lines with no sprite at all; the sprite layer's visibility is checked once per whole tile and
once per pixel drawn dot by dot.

Dots 257-340 of every rendered line still run one dot at a time (`Renderer#run_dot`):

- the horizontal copy at 257;
- the sprite evaluation at 257;
- `OAMADDR` reset every dot from 257 to 320;
- 8 sprite slots of 8 dots, with their two pattern fetches and a load;
- the next line's first two tiles from 321.

For Super Mario Bros. 3 the sprite pattern fetches are also what clocks MMC3's scanline counter (plan 21). So their
dot, through `Ppu::DotClock`, must stay exact.

## Scope

In, each step measured A/B and kept only if it pays (plan 25, decision 4):

1. **Tiles without sprites.** When the sprite line is loaded, record which 8-column groups hold an opaque sprite pixel
   (for example a 32-bit mask). A whole tile with no sprite pixel composes the background alone, skipping the sprite
   lookup, the visibility check and the multiplexer. A line with no sprites skips it for all 32 tiles.
   `PixelComposer#draw_background_tile` already draws a tile without reading the sprite line (plan 30, decision 6):
   a sprite-free tile can take it, as a tile whose sprites are hidden does.
2. **Whole sprite slots.** Like `WHOLE_TILE` (plan 28, decision 6): when a range covers a slot's 8 dots, run them as one
   unrolled sequence. That sequence covers:
   - `OAMADDR` reset;
   - the low and high pattern fetches, with the dot clock moved to each fetch's dot;
   - the load into the sprite line.

   Split slots keep the per-dot path.
3. **The rest of the horizontal blank.** Measure what remains of dots 257-340 after step 2 (the horizontal copy, the
   vertical copies on the pre-render line, the first two tiles of the next line) and unroll it only if it pays.

Out:

- The sprite evaluation's internal timing. It stays one call at dot 257 (plan 14, decision 2), and the overflow bug
  stays as modelled.
- Accuracy shortcuts, such as the sprite 0 hit per line instead of per pixel (architecture decision 77). Any such change
  belongs to the optional fast mode.

## Design notes

- **Exactness.**
  - The sprite line for line N is filled on line N − 1's dots 257-320 and only read on line N's dots 1-256.
  - A sprite-free mask built at load time is therefore exact for the whole of line N.
  - The sprite 0 hit is still decided per pixel, wherever both layers are opaque.
  - `OAMADDR` is reset on every dot 257-320 (https://www.nesdev.org/wiki/PPU_registers). A whole slot sets it once.
    This is exact because no register access happens inside a range.
- **Empty slots fetch tile $FF.** Those fetches reach the bus and MMC3's A12 watch (`SpriteFetcher`, "dummy fetches
  to tile $FF"), so a whole slot keeps them.
- **Hot path rules** (`docs/architecture.md`, Hot paths): the mask is an integer, filled in `SpriteLine#place`, with
  no allocation.

## Open decisions

1. **Where the mask lives**: `SpriteLine`, which already owns the entries, or the renderer. Recommendation:
   `SpriteLine`, reset by `clear` and set by `place`.
2. **The flag for a whole slot**: a new `RenderSchedule` flag on dots 257, 265, …, 313, as `WHOLE_TILE`.
   Recommendation: yes, the same pattern as plan 28.

## Tasks

- [ ] Re-profile (`rake bench:profile`) and confirm the shares before starting.
- [ ] Units, test first, one step at a time, each measured:
  - [ ] the sprite line's mask of occupied tiles;
  - [ ] the renderer's sprite-free whole tile;
  - [ ] `RenderSchedule`'s whole-slot flag;
  - [ ] the renderer's whole slot, with the clock on each fetch's dot;
  - [ ] whatever of the rest of 257-340 is kept.
- [ ] The whole suite and the test ROMs stay green, including:
  - `sprite_hit_tests_2005.10.05`;
  - `sprite_overflow_tests`;
  - `mmc3_test_2`;
  - the SMB3 console spec and its MMC3 IRQ example from plan 28.
- [ ] Measure and record in `docs/benchmarks.md`, kept and not kept steps alike.
- [ ] `docs/architecture.md`: rendering, decisions log.

## Acceptance criteria

- [ ] `rake bench:frames` digests unchanged from the previous kept step.
- [ ] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green.
- [ ] The new frames per second recorded per configuration. One of:
  - 60 fps under one configuration with the window's audio free of crackles (M7 closes);
  - the remaining gap quantified per component.
- [ ] If the gap remains after plans 29-31: the accuracy shortcuts, each with its measured gain and the tests it puts
      at risk, proposed to the user for the optional fast mode (architecture decision 77).

## References

- PPU rendering — https://www.nesdev.org/wiki/PPU_rendering
- PPU sprite evaluation — https://www.nesdev.org/wiki/PPU_sprite_evaluation
- PPU sprite priority — https://www.nesdev.org/wiki/PPU_sprite_priority
- PPU OAM — https://www.nesdev.org/wiki/PPU_OAM
- PPU registers (OAMADDR) — https://www.nesdev.org/wiki/PPU_registers
- MMC3 (A12's filter) — https://www.nesdev.org/wiki/MMC3
