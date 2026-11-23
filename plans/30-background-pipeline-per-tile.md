# 30 — Background pipeline per tile

**Depends on:** 28

## Goal

Cut the cost of a whole tile, which plan 28 runs as one unrolled sequence (`Renderer#run_tile`, architecture decision
76), without changing a single pixel or fetch. The frame and audio digests of `rake bench:frames` must stay those of
plan 28 (f0903fbc59bf frame, 10369a5b40df audio).

## Context

After plan 28, the background's work is the largest part of a Super Mario Bros. 3 frame under YJIT. Its profile shares
(`docs/benchmarks.md`, Findings, plan 28):

| Part | Share | ms per frame |
|---|---|---|
| Pixel composition: `Renderer#draw`, the shift registers, `Picture#draw`, palette RAM, the multiplexer | ~29% | ~10 |
| Background fetches and v updates: fetcher, `PpuBus`, nametables, mapper, MMC3's A12 watch | ~17% | ~6 |
| Loops: `Console#run_frame`, `Ppu#catch_up`, `Renderer#run_dots` and `#run_dot`, the frame timing | ~13% | ~4.5 |

These three change together: they share the shift registers, the fetch latches and the tile sequence. A whole tile
today does:

- 8 `draw` calls, each extracting 4 bits from 4 shift registers under fine X;
- 8 `shift` calls, each shifting 4 registers;
- 8 `Picture#draw` calls, each reading palette RAM through its mirror table, masking for greyscale, adding emphasis
  and storing.

That is 61 440 pixels a frame, each through about 3 method calls.

## Scope

In, each step measured A/B and kept only if it pays (plan 25, decision 4):

1. **A colour per palette entry, precomputed.** `Ppu::Picture` keeps the 32 final pixel values: palette RAM's colour,
   the greyscale mask and the emphasis bits. It rebuilds them when any of those changes:
   - a palette RAM write;
   - a greyscale or emphasis change through PPUMASK.

   All three are register writes, which catch the PPU up first (plan 12, decision 1), so the table is never stale for
   a pixel. Each pixel becomes a table read and a store, with no palette RAM read per pixel.
2. **Fewer calls per pixel in the whole tile.** The renderer writes into the picture's drawn buffer row directly,
   through a narrow interface the picture owns (open decision 1). The buffer swap on `complete_frame` must hand the
   renderer the new buffer.
3. **Pattern bits decoded by table.** A load-time table interleaves a pattern byte's bits, so the two planes of a tile
   become 8 two-bit pattern values. Fine X picks the window across the current and the next tile. A whole tile then
   reads its 8 pixels by shifts of a precomputed value, instead of shifting 4 registers 8 times. The per-dot path
   (split tiles, dots 321-336) must read the same state, so both paths stay one model (open decision 2).
4. **Fetch path.** Measure the call chain of each fetch (`BackgroundFetcher` → `PpuBus#read` → nametable or mapper,
   plus A12's watch). Candidates:
   - Hand the bus the board's mirroring when it changes, instead of asking for it on every nametable access. This is
     a change to the mapper interface (`mirroring`, "asked on every nametable access"). Board writes catch the PPU up
     first, so it is exact.
   - Keep the two pattern fetches separate. Merging them would move the second fetch's A12 time, which MMC3's filter
     may see (plan 21, decision 2). It is listed only to be ruled out.

Out:

- Sprites and dots 257-340: plan 31.
- Accuracy shortcuts, such as drawing a scanline at once regardless of writes in the middle of it (architecture
  decision 77). Any such change belongs to the optional fast mode.

## Design notes

- **Exactness.** A whole tile runs only inside a range, and a range has no register write within it (plan 28,
  decision 4). So everything a tile reads — fine X, palette RAM, PPUMASK, the pattern table and the mirroring — is
  fixed for the tile. Any precomputation made at a register write is exact.
- **Sprite pixels** are still composed per pixel: `@sprite_entries[x]`, visibility, and the multiplexer where both
  layers are opaque. Plan 31 decides the sprite side. This plan must keep the composition order and the sprite 0 hit
  check where they are.
- **Left column.** PPUMASK bits 1 and 2 hide columns 0-7 per layer (`LayerVisibility#first_visible_column`). Only
  the first tile of a line can be affected, so the whole-tile path may branch once per tile, not once per pixel.
- **Hot path rules** (`docs/architecture.md`, Hot paths): no allocation per tile or pixel, preallocated arrays,
  integer masks with their glossary tags. Plan 28 measured a `while` + `case` loop slower than the unrolled sequence
  under YJIT, so each restructuring is measured before it is kept.

## Open decisions

1. **How the renderer reaches the drawn buffer.**
   - (a) `Picture#draw_row(y, x, entries)` takes a tile's 8 entries at once.
   - (b) The renderer holds the drawn buffer and the colour table, and `complete_picture` re-hands them.

   Recommendation: (b) if (a) measures no better, documenting the contract in the frame buffer section.
2. **The shift registers' representation**: the hardware's four 16-bit registers, or two-bit pixel values per tile.
   Recommendation: two-bit values if they measure faster, with a spec proving that a tile run whole and the same tile
   in pieces draw the same pixels (plan 28's equivalence check).
3. **Mirroring pushed or asked.** Recommendation: pushed, if it measures at least a few percent. It changes the mapper
   interface table in `docs/architecture.md`.

## Tasks

- [ ] Re-profile (`rake bench:profile`) and confirm the shares before starting.
- [ ] Units, test first, one step at a time, each measured:
  - [ ] the picture's colour table and its rebuild on palette, greyscale and emphasis changes;
  - [ ] the renderer's drawing of a whole tile through it;
  - [ ] the pattern decoding and its use on both the whole-tile and the per-dot paths;
  - [ ] the fetch path change, if kept.
- [ ] The whole suite and the test ROMs stay green, including:
  - the nestest golden frame;
  - `sprite_hit_tests_2005.10.05`;
  - `mmc3_test_2`;
  - the SMB3 console spec.
- [ ] Measure and record in `docs/benchmarks.md`, kept and not kept steps alike.
- [ ] `docs/architecture.md`: rendering, frame buffer contract, mapper interface if it changes, decisions log.

## Acceptance criteria

- [ ] `rake bench:frames` digests unchanged from plan 28 (f0903fbc59bf frame, 10369a5b40df audio).
- [ ] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green.
- [ ] The new frames per second recorded per configuration. One of:
  - 60 fps under one configuration with the window's audio free of crackles (M7 closes);
  - the remaining gap quantified per component.

## References

- PPU rendering — https://www.nesdev.org/wiki/PPU_rendering
- PPU scrolling (fine X, the tile and attribute fetches) — https://www.nesdev.org/wiki/PPU_scrolling
- PPU pattern tables — https://www.nesdev.org/wiki/PPU_pattern_tables
- PPU palettes — https://www.nesdev.org/wiki/PPU_palettes
- PPU registers (PPUMASK) — https://www.nesdev.org/wiki/PPU_registers
- Colour emphasis — https://www.nesdev.org/wiki/Colour_emphasis
- MMC3 (A12's filter) — https://www.nesdev.org/wiki/MMC3
