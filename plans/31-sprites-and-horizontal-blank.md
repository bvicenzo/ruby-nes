# 31 — Sprites and the horizontal blank

**Status:** done (2026-11-23)

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

Profiled again before starting (vernier, YJIT, 200 frames after the warm-up, self time):

| Part | Methods | Share |
|---|---|---|
| Pixel | `Renderer#run_tile` 13.0, `PixelComposer#draw_tile` 7.5, `#background_window` 1.3, `#draw`/`#output_pixel` ~1.3 | ~23% |
| Loops | `Renderer#run_dots` 11.7, `Console#run_frame` 6.5, `Renderer#run_dot` 2.2 | ~20% |
| Sprites | `SpriteRenderer#run_steps` 11.5, `SpriteEvaluation#select_sprites` 1.4, `SpriteLine#place` 0.6, fetch 0.4 | ~14% |
| Background fetches | `Mappers::Base#ppu_read` 6.6, `BackgroundFetcher#fetch_attribute` 2.6, the others ~5 | ~16% |

- `SpriteRenderer#run_steps` is called on every dot 257-320 (64 a line, about 15 000 a frame) only because OAMADDR is
  reset on each: whole slots go after that.
- `Renderer#run_dots` also walks, dot by dot, the 20-odd lines with no step at all (240-260): 341 iterations each,
  about 7 000 a frame, a fifth of the loop's iterations. Measured, they cost only about 3 µs a line (see the findings).

## Findings that reshaped the plan

Prototypes over 8061014 (throwaway, YJIT), measured A/B interleaved against a worktree of the base: whole frames
(median of 5 runs of 60 after the 1200 warm-up frames) and `Renderer#run_dots` over a visible line's dots 1-340, or
only the dots a step touches. This machine drifts by a few percent between rounds, so each step took 3-8 rounds. Every
variant kept the frame digest.

| Step (cumulative) | Frame | Visible line 1-340 | Kept |
|---|---|---|---|
| Base | ~21.5 ms | ~64 µs | — |
| Sprite-free whole tiles | ~-2% | ~-3% | yes |
| + whole slots (first dot through `run_dot`) | ~17.5 ms | ~49 µs | yes |
| + a slot's first dot skipped when it only resets OAMADDR (all but 257) | ~-3% | ~-3% | yes |
| + the next line's two tiles whole (dots 321-340: 3.1 → 1.6 µs) | ~-2% | — | yes |
| Lines with no step returning at once (3 µs → 0.05 µs a line, about 20 lines) | ~-0.3% | — | no: below the noise |

All kept steps together: about 21.5 ms became about 17.2 ms per frame (-20%).

## Scope

In, each step measured A/B and kept only if it pays (plan 25, decision 4):

1. **Tiles without sprites.** When the sprite line is loaded, record which 8-column groups hold an opaque sprite pixel
   (decision 1). A whole tile with no sprite pixel composes the background alone, skipping the sprite
   lookup, the visibility check and the multiplexer. A line with no sprites skips it for all 32 tiles.
   `PixelComposer#draw_background_tile` already draws a tile without reading the sprite line (plan 30, decision 6):
   a sprite-free tile can take it, as a tile whose sprites are hidden does.
2. **Whole sprite slots.** Like `WHOLE_TILE` (plan 28, decision 6): when a range covers a slot's 8 dots, run them as one
   unrolled sequence. That sequence covers:
   - `OAMADDR` reset;
   - the low and high pattern fetches, with the dot clock moved to each fetch's dot;
   - the load into the sprite line.

   Split slots keep the per-dot path.
3. **The rest of the horizontal blank.** Measure what remains of dots 257-340 after step 2 and unroll it only if it
   pays. Candidates, each measured:
   - lines with no step at all (post-render and VBlank) return at once instead of walking their 341 dots: measured
     about 0.3% of a frame, not kept;
   - the next line's two tiles (321-336) as whole tiles without pixels: the reload, 8 shifts at once, the four fetches
     and coarse X. Kept (decision 5).

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
- **Dot 257** is slot 0's first dot and also reloads, copies the horizontal position, clears the line and evaluates.
  A whole slot runs its first dot the usual way (`run_dot`) only when it has a step besides the slot's reset of OAMADDR,
  that is on 257; then the sprite renderer resets OAMADDR, makes the two fetches, the clock on each one's dot, and
  loads. The other 7 resets change nothing: no register access (nor OAM DMA, which
  writes through `$2004` and catches the PPU up first) happens inside a range, and the evaluation reads OAM through
  `Oam#byte` without touching OAMADDR.
- **Hot path rules** (`docs/architecture.md`, Hot paths): the tile flags are one preallocated array filled in place,
  with no allocation.

## Decisions

1. **The occupied tiles live in `SpriteLine`**, as an array of 32 flags, one per 8-column group of the screen, the same
   array for the life of the line (`occupied_tiles`, handed by `SpriteRenderer` like `line_entries`): `clear` empties
   it in place, `place` marks the group of each opaque pixel it puts. Not a 32-bit Integer: an Integer cannot be shared
   by reference, so the renderer would need a call per tile to read it, and testing a tile's bit would be a shift by a
   varying amount, a method call under YJIT (plan 30, findings).
2. **`RenderSchedule::WHOLE_SLOT`** marks dots 257, 265, …, 313 of the visible line only, like `WHOLE_TILE`. The
   pre-render line (one of 262, loading nothing, with the vertical copies over its slots) stays dot by dot.
   `Renderer#run_dots` tests `RenderSchedule::WHOLE_STEPS` (`WHOLE_TILE | WHOLE_SLOT | WHOLE_NEXT_LINE_TILE`) once per
   iteration and picks the sequence only in the branch taken: all are `RenderSchedule::SEQUENCE_DOTS`, 8 dots, and the
   schedule's spec pins the steps of the 7 dots after each sequence's first.
3. **The sprite renderer runs a whole slot** (`SpriteRenderer#run_slot`), holding the shared `DotClock`: it resets
   OAMADDR, moves the clock to each fetch's dot, fetches and loads (tell, don't ask). The renderer runs the slot's first
   dot through `run_dot` only when it holds more than the slot's own steps (dot 257), then tells it: skipping
   `run_dot` on the other 7 measured about 3%.
4. **Order:** sprite-free tiles, whole slots, then the rest; each prototyped and measured A/B interleaved first, as in
   plans 28-30.
5. **The next line's two tiles run whole** (`RenderSchedule::WHOLE_NEXT_LINE_TILE` on dots 321 and 329 of both
   rendering lines): the reload when the dot has one, the 8 shifts at once, the four fetches with the clock on each
   one's dot, and coarse X, as a whole tile without its pixels. Lines with no step are not skipped: about 0.3% of a
   frame, below the noise.
6. **`Ppu::Renderer` keeps growing in one class**: past RuboCop's class length, the cop is disabled on the class with
   its reason (the hot path inline, called through self). Extracting the four shift registers into their own object
   was the alternative, not chosen.

## Tasks

- [x] Re-profile (`rake bench:profile`) and confirm the shares before starting.
- [x] Units, test first, one step at a time, each measured:
  - [x] `SpriteLine#occupied_tiles`, and `SpriteRenderer#occupied_tiles` handing it;
  - [x] the renderer's sprite-free whole tile;
  - [x] `RenderSchedule`'s whole-slot and whole next-line tile flags;
  - [x] `SpriteRenderer#run_slot`, with the clock on each fetch's dot;
  - [x] the renderer's whole slot;
  - [x] the renderer's whole next-line tile (`WHOLE_NEXT_LINE_TILE`).
- [x] The whole suite and the test ROMs stay green, including:
  - `sprite_hit_tests_2005.10.05`;
  - `sprite_overflow_tests`;
  - `mmc3_test_2`;
  - the SMB3 console spec and its MMC3 IRQ example from plan 28.
- [x] Measure and record in `docs/benchmarks.md`, kept and not kept steps alike.
- [x] `docs/architecture.md`: rendering, the dot clock, decisions log (88-91).

## Acceptance criteria

- [x] `rake bench:frames` digests unchanged from the previous kept step: f0903fbc59bf frame, 10369a5b40df audio.
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green (the raylib window specs left out without a display, as in plans
      22-30): 2816 examples, 0 failures, and RuboCop clean, run apart.
- [x] Each step measured A/B interleaved and recorded in `docs/benchmarks.md`, kept or not.
- [x] The new frames per second recorded per configuration. One of:
  - 60 fps under one configuration with the window's audio free of crackles (M7 closes);
  - the remaining gap quantified per component. Met: the emulation runs at 61.5 fps under YJIT, but the window showed
    50-52 fps; its presentation (`Frontends::Palette.rgb`, about 2.6 ms a frame) is the gap, handed to plan 32.
- [x] If the gap remains after plans 29-31: the accuracy shortcuts, each with its measured gain and the tests it puts
      at risk, proposed to the user for the optional fast mode (architecture decision 77). Not needed: the emulation
      reached 60 fps exactly; what remains is the window's presentation, which an exact change can cut (plan 32).

## What was done

- **Occupied tiles.** `Ppu::SpriteLine#occupied_tiles` flags each group of 8 columns holding an opaque sprite pixel; a
  whole tile the flags leave clear composes the background alone.
- **Whole slots.** `RenderSchedule::WHOLE_SLOT` on 257, 265, …, 313 of a visible line: the renderer runs the slot's
  first dot only where it has more than the slot's own steps (257), then `SpriteRenderer#run_slot` resets OAMADDR once,
  makes the two fetches with the shared dot clock on their dots, and loads. The clock is a required keyword of the
  sprite renderer.
- **Whole next-line tiles.** `RenderSchedule::WHOLE_NEXT_LINE_TILE` on 321 and 329 of both rendering lines: a whole
  tile without its pixels. `RenderSchedule::SEQUENCE_DOTS` names the 8 dots every whole sequence takes, and the
  schedule's spec pins the steps of the 7 dots after each sequence's first.
- **Not kept:** skipping the lines with no step (about 0.3% of a frame).
- **Measured** (`rake bench:frames`):

  | Configuration | Plan 30's final | Now |
  |---|---|---|
  | interpreter | 14.5 fps | 17.2 fps |
  | yjit | 46.6 fps | 61.5 fps |
  | zjit | 39.5 fps | 44.5 fps |

  A visible line went from ~64 to ~43 µs; `SpriteRenderer#run_steps` from about 11% of a frame to 1%. Digests
  unchanged.
- **The window.** Played by the user in the raylib window: the picture, the status bar and the sound are right, at
  50-52 fps. `Frontends::Palette.rgb` takes about 2.6 ms a frame on top of the emulation's 16.3 ms; plan 32 takes the
  window's presentation.
- **Independent review.** No correctness bugs. Applied: the clock required in `SpriteRenderer`; the 8-dot sequence
  length named and the 7 dots after each sequence's first pinned in the schedule's spec; `run_whole_sequence`; decision
  2 naming `WHOLE_STEPS`; a spec leaf renamed to its outcome; stale checkboxes. Not changed: `run_tile` re-reading its
  first dot's steps (hot path, cosmetic only).

## References

- PPU rendering — https://www.nesdev.org/wiki/PPU_rendering
- PPU sprite evaluation — https://www.nesdev.org/wiki/PPU_sprite_evaluation
- PPU sprite priority — https://www.nesdev.org/wiki/PPU_sprite_priority
- PPU OAM — https://www.nesdev.org/wiki/PPU_OAM
- PPU registers (OAMADDR) — https://www.nesdev.org/wiki/PPU_registers
- MMC3 (A12's filter) — https://www.nesdev.org/wiki/MMC3
