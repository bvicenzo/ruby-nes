# 30 — Background pipeline per tile

**Status:** done (2026-11-23)

**Depends on:** 28

## Goal

Cut the cost of a whole tile, which plan 28 runs as one unrolled sequence (`Renderer#run_tile`, architecture decision
76), without changing a single pixel or fetch. The frame and audio digests of `rake bench:frames` must stay those of
plans 28 and 29 (f0903fbc59bf frame, 10369a5b40df audio).

## Context

After plan 29, Super Mario Bros. 3 takes about 29.3 ms per frame under YJIT (34.1 fps), about 12.7 ms above the 16.6
ms budget, and the APU is out of the way (~2%). Profiled again before starting (vernier, YJIT, 200 frames after the
warm-up, self time):

| Part | Methods | Share |
|---|---|---|
| Pixel composition | `Renderer#run_tile` 15.3, `#draw` 10.9, `Picture#draw` 4.8, `#shift` 1.9, `Integer#>>` 1.8, `PaletteRam#read` 1.2, `#reload` 0.4 | ~36% |
| Background fetches | `BackgroundFetcher#fetch_attribute` 6.0, `Mappers::Base#ppu_read` 4.7, `PpuBus#read` 3.0, `Nametables#vram_index` 2.7, `Mmc3#ppu_read` 1.0, the other fetches ~2.5 | ~21% |
| Loops | `Renderer#run_dots` 8.2, `Console#run_frame` 4.1, `Renderer#run_dot` 1.7, ... | ~15% |
| Sprites (plan 31) | `SpriteRenderer#run_steps` 8.2, the evaluation 0.9 | ~9% |

`Integer#>>` shows as a C call: the shifts by a variable amount in `Renderer#draw` (bit 15 − fine X) are not
specialised by YJIT.

These parts change together: they share the shift registers, the fetch latches and the tile sequence. A whole tile
today does:

- 8 `draw` calls, each extracting 4 bits from 4 shift registers under fine X;
- 8 `shift` calls, each shifting 4 registers;
- 8 `Picture#draw` calls, each reading palette RAM through its mirror table, masking for greyscale, adding emphasis
  and storing.

That is 61 440 pixels a frame, each through about 3 method calls.

## Findings that reshaped the plan

Prototypes over 65e1705 (throwaway, YJIT), measured in two ways: whole frames A/B interleaved, and the time of
`Renderer#run_dots` over a visible line's dots 1-256 after the 1200 warm-up frames, A/B interleaved (more stable on
this noisy machine, ±2%). Every full-frame variant kept the digests.

| Variant (cumulative) | µs per visible line | Kept |
|---|---|---|
| Base | ~70-77 | — |
| Colours precomputed + direct buffer + window, a `compose` call per pixel | ~71 | partly |
| + the 8 pixels composed inline in one method (no call per pixel) | ~53 | yes |
| + the window computed inline in `run_tile` instead of its own method | ~54-57 | no |
| + the fetcher reading the nametables and the board without `PpuBus#read` | ~53 | no: no gain |
| + mirroring kept by the nametables instead of a Hash lookup per access (upper bound) | ~50.5 | yes, pushed |
| + the attribute address and quadrant from tables indexed by v | ~43.5 | yes |
| + one spread table per bit plane, instead of shifting a table's value | ~40.5 | yes |
| `Mappers::Base#ppu_read` without its local | ~40.5 | no: no gain |
| Mirroring cached by an identity check of the board's answer (exact, no interface change) | ~41-43 | no: pushed is better |

Whole frames, all kept variants together: about 30.0 ms became 23.2 ms (-22%).

**YJIT findings.**

- `Integer#>>` and `Integer#<<` by an amount that varies (fine X, the attribute quadrant) are C calls: YJIT
  specialises a shift only for the amounts it has seen. A multiplication by a power of two from a table, then a
  constant shift, replaces them.
- The calls per pixel dominate: three per pixel (`draw`, `shift`, `Picture#draw`) cost more than all the
  arithmetic.
- Built test first, the composition moved to `Ppu::PixelComposer` (the renderer passed 200 lines). Its unrolled
  `draw_tile` first computed the frame index itself, `(y × WIDTH) + x`, and the line took 57 µs instead of 44: the
  same index handed in computed by the caller, or the literal 256, cost nothing. Replacing the masks' constants with
  literals changed nothing measurable (44.6 against 44.1 µs), so they keep their names. Microbenchmarks of these
  effects were not reliable (a loop's own compilation and constant cache fills moved them by 4×); only the line
  benchmark on the real renderer was.

## Scope

In, each step prototyped and measured A/B interleaved against a worktree of the base, kept only if it pays (plan 25,
decision 4), then built test first:

1. **A colour per palette entry, precomputed.** `Ppu::Picture` keeps the 32 final pixel values: palette RAM's colour,
   the greyscale mask and the emphasis bits. It rebuilds them when any of those changes:
   - a palette RAM write, which `PpuBus::PaletteRam` tells its observer (decision 4);
   - a greyscale or emphasis change through PPUMASK.

   All three are register writes, which catch the PPU up first (plan 12, decision 1), so the table is never stale for
   a pixel. Each pixel becomes a table read and a store, with no palette RAM read per pixel.
2. **Fewer calls per pixel.** The renderer writes into the picture's drawn buffer directly, through the picture's
   colour table (decision 1). The buffer swap on `complete_frame` hands the renderer the new buffer.
3. **A whole tile reads a window of 8 pixels.** The four 16-bit shift registers stay the only model (decision 2). A
   whole tile reads the 8 bits under fine X of each register at its start, spreads each byte into the nibbles of a
   32-bit value through a load-time table, and draws its 8 pixels from that value by literal shifts. Since a whole
   tile has no reload after its first dot, its 8 shifts become one shift by 8 at its end. The per-dot path does not
   change.
4. **Fetch path.** Each candidate measured, kept only if it pays:
   - the fetcher reads the nametables and the board directly, without `PpuBus#read`'s decoding: a nametable or
     attribute address is always in $2000-$2FFF, a pattern address always below $2000 (precedent: the picture reads
     palette RAM directly, plan 25, decision 7). Measured: no gain, not kept;
   - the board hands the nametables its mirroring when it changes, instead of being asked on every nametable access
     (decision 3);
   - the attribute address and quadrant shift from a table indexed by v's bits, instead of their arithmetic.

   The two pattern fetches stay separate: merging them would move the second fetch's A12 time, which MMC3's filter
   may see (plan 21, decision 2).

Out:

- Sprites and dots 257-340: plan 31.
- Accuracy shortcuts, such as drawing a scanline at once regardless of writes in the middle of it (architecture
  decision 77). Any such change belongs to the optional fast mode.

## Design notes

- **Exactness.** A whole tile runs only inside a range, and a range has no register write within it (plan 28,
  decision 4). So everything a tile reads — fine X, palette RAM, PPUMASK, the pattern table and the mirroring — is
  fixed for the tile. Any precomputation made at a register write is exact.
- **Why not two-bit values per pixel.** The two tiles in flight are 16 pixels of 4 bits, 64 bits: past a Fixnum (62
  bits), so a Bignum allocated per tile. A tile only ever shows the 8 pixels from fine X on, 32 bits.
- **The window.** At a whole tile's first dot, after its reload, pixel i (0-7) is bit 15 − fine X − i of each
  register (https://www.nesdev.org/wiki/PPU_rendering, https://www.nesdev.org/wiki/PPU_scrolling): the byte
  `(register >> (8 − fine X)) & $FF`, bit 7 first.
- **Sprite pixels** are still composed per pixel: `@sprite_entries[x]`, visibility, and the multiplexer where both
  layers are opaque. Plan 31 decides the sprite side. This plan keeps the composition order and the sprite 0 hit
  check where they are.
- **Left column.** PPUMASK bits 1 and 2 hide columns 0-7 per layer (`LayerVisibility#first_visible_column`). Only
  the first tile of a line can be affected, so the whole-tile path may branch once per tile, not once per pixel.
- **Hot path rules** (`docs/architecture.md`, Hot paths): no allocation per tile or pixel, preallocated arrays,
  integer masks with their glossary tags. Plan 28 measured a `while` + `case` loop slower than the unrolled sequence
  under YJIT, so each restructuring is measured before it is kept.

## Decisions

1. **The renderer holds the drawn buffer and the colour table** (option b): the picture hands both, the colour table
   being one array mutated in place, and `complete_picture` takes the new drawn buffer after the swap. A
   `Picture#draw_row` taking a tile's 8 entries (option a) is not prototyped: it needs an array of entries and a loop,
   and plan 28 measured a loop slower than the unrolled sequence. The contract goes into the frame buffer section.
2. **The four 16-bit shift registers stay the model.** A whole tile reads its window under fine X through a load-time
   table and shifts by 8 once; the per-dot path is unchanged. A spec checks that a whole tile with fine X other than
   0 draws the same pixels as the same tile dot by dot.
3. **Mirroring pushed**, if it measures at least a few percent: `Mappers::Base` gets a private setter the boards that
   change their mirroring (AxROM, MMC1, MMC3) call, which tells the nametables; they keep the page array. Exact,
   since board writes catch the PPU up first. It changes the mapper interface table.
4. **Palette RAM tells its observer on every write** (tell, don't ask), and the picture, registered as that observer,
   rebuilds its 32 colours: palette writes are a few dozen a frame, in VBlank. The Ppu telling the picture after a
   PPUDATA write would have to decode the address itself.
5. **Order:** colours, then the direct buffer, then the window, then the fetch path; each prototyped and measured
   A/B interleaved first, as in plans 28 and 29.
6. **A whole tile composes its 8 pixels inline**, in one method per case: background only (the sprite layer hidden
   for the tile) and both layers. A layer's first visible column is 0, 8 or 256 and a whole tile starts on a multiple
   of 8, so each layer is visible or hidden for the whole tile: decided once per tile. A hidden background is a window
   of 0. The window masks the attribute bits with the opaque pattern bits, so a transparent pixel's nibble is 0.
7. **No shift by a varying amount on the hot path:** fine X picks a power of two from a table, multiplied in, then a
   constant shift (the window); the attribute quadrant the same way. One spread table per bit plane, so no shift of
   a table's value.
8. **Fetch path:** the attribute address and the quadrant's multiplier come from two tables of 4096 entries indexed
   by v's low 12 bits; the mirroring is pushed (decision 3). The fetcher keeps reading through `PpuBus#read`:
   bypassing it measured nothing.

## Tasks

- [x] Re-profile (`rake bench:profile`) and confirm the shares before starting.
- [x] Units, test first, one step at a time, each measured:
  - [x] `PpuBus::PaletteRam` telling its observer of each write;
  - [x] the picture's colour table and its rebuild on palette, greyscale and emphasis changes;
  - [x] the renderer drawing into the drawn buffer through the colour table, by `Ppu::PixelComposer`;
  - [x] the whole tile's window, with its equivalence to the per-dot path;
  - [x] the attribute fetch by tables;
  - [x] the mirroring pushed: `Mappers::Base` and the boards that change it, `PpuBus::Nametables`.
- [x] The whole suite and the test ROMs stay green, including:
  - the nestest golden frame;
  - `sprite_hit_tests_2005.10.05`;
  - `mmc3_test_2`;
  - the SMB3 console spec.
- [x] Measure and record in `docs/benchmarks.md`, kept and not kept steps alike.
- [x] `docs/architecture.md`: rendering, frame buffer contract, mapper interface, hot paths, readability (exception
      3), decisions log (83-87).

## Acceptance criteria

- [x] `rake bench:frames` digests unchanged from plans 28 and 29 (f0903fbc59bf frame, 10369a5b40df audio) after every
      kept step.
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green: the slow suite, 2789 examples, 0 failures, and RuboCop clean,
      run apart. The raylib window specs (`frontends/raylib_spec.rb`, `command_line/raylib_window_spec.rb`,
      `frontend_benchmark/command_line_spec.rb`) segfault without a display in this environment and were left out, as
      in plans 22-29.
- [x] Each step measured A/B interleaved and recorded in `docs/benchmarks.md`, kept or not.
- [x] The new frames per second recorded per configuration. One of:
  - 60 fps under one configuration with the window's audio free of crackles (M7 closes);
  - the remaining gap quantified per component.

## What was done

- **Colours precomputed.** `Ppu::Picture#colours` holds the final pixel of each palette entry, rebuilt when
  `PpuBus::PaletteRam` tells it of a write (its observer) or greyscale or emphasis change.
- **The pixel composer.** `Ppu::PixelComposer` composes the background's and the sprites' entries and stores the pixel
  into the picture's drawn frame; it completes the frame and takes the new buffer. A whole tile is one call drawing 8
  pixels unrolled, the background alone when the tile's sprites are hidden. It was extracted when the renderer passed
  200 lines.
- **The window.** `Renderer#run_tile` reads a whole tile's 8 pixels under fine X from the four registers through a
  spread table per register, and shifts by 8 once; the per-dot path is unchanged. A spec runs two tiles whole and in
  pieces from the same state.
- **Fetches.** The attribute address and quadrant come from two tables indexed by v's low 12 bits; the board tells the
  nametables every mirroring it selects (`nametables=`, `mirroring_changed`). Bypassing `PpuBus#read` measured nothing
  and was not kept.
- **Measured** (`rake bench:frames`):

  | Configuration | Plan 29's final | Now |
  |---|---|---|
  | interpreter | 10.2 fps | 14.5 fps |
  | yjit | 34.1 fps | 46.6 fps |
  | zjit | 30.3 fps | 39.5 fps |

  A visible line went from ~70 to ~35 µs; whole frames A/B, 28.4 to 20.7 ms (-27%). Digests unchanged.
- **The gap left:** about 4-5 ms per frame under YJIT. Per component, in `docs/benchmarks.md`: pixel ~23%, the loops
  ~22%, fetches ~16%, sprites ~14%, CPU ~8%, APU ~2%. Plan 31 is next.
- **YJIT findings** (`docs/benchmarks.md`): a shift by a varying amount is a method call; calls per pixel dominate; an
  unrolled method computing its own frame index into a local ran a third slower.
- **Independent review.** No correctness bugs. Applied: the final table in `docs/benchmarks.md`; Readability exception
  3 for the nibble positions; the frame-completion invariant in the frame buffer contract; the composer built inside
  the renderer (no unused keyword); the one-owner rule for the palette RAM's observer and the board's nametables; stale
  comments; a duplicate renderer leaf removed; the sprite priority reference; decision 85 split in two; long doc lines.
  Not changed: the palette RAM spec's observer contexts and the whole-tile contexts' own visibility `let`s, both
  required by the project's RSpec cops (no nested subject or `let` redefinition).

## References

- PPU rendering — https://www.nesdev.org/wiki/PPU_rendering
- PPU scrolling (fine X, the tile and attribute fetches) — https://www.nesdev.org/wiki/PPU_scrolling
- PPU pattern tables — https://www.nesdev.org/wiki/PPU_pattern_tables
- PPU attribute tables — https://www.nesdev.org/wiki/PPU_attribute_tables
- PPU palettes — https://www.nesdev.org/wiki/PPU_palettes
- PPU sprite priority (the composition) — https://www.nesdev.org/wiki/PPU_sprite_priority
- PPU registers (PPUMASK) — https://www.nesdev.org/wiki/PPU_registers
- Colour emphasis — https://www.nesdev.org/wiki/Colour_emphasis
- Mirroring — https://www.nesdev.org/wiki/Mirroring
- MMC3 (A12's filter) — https://www.nesdev.org/wiki/MMC3
