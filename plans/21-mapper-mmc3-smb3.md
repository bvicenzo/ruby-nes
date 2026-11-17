# 21 — Mapper MMC3 and Super Mario Bros. 3

**Depends on:** 14, 18, 20

## Goal

Mapper 4 (MMC3) with its scanline IRQ, and Super Mario Bros. 3 playable. Milestone M5.

## Context

Registers (even/odd addresses within each range):

| Address | Register |
|---|---|
| `$8000` even | bank select: target R0–R7 (bits 0–2), PRG mode (bit 6), CHR A12 inversion (bit 7) |
| `$8001` odd | bank data for the selected register |
| `$A000` even | mirroring (0 vertical, 1 horizontal) |
| `$A001` odd | PRG-RAM protect |
| `$C000` even | IRQ latch |
| `$C001` odd | IRQ reload (clears the counter; reloaded on the next clock) |
| `$E000` even | IRQ disable and acknowledge |
| `$E001` odd | IRQ enable |

Banking: PRG in 8 KiB banks (R6, R7, second-to-last fixed, last fixed; PRG mode swaps `$8000` and `$C000`). CHR: R0,
R1 are 2 KiB, R2–R5 are 1 KiB; A12 inversion swaps the halves.

IRQ counter: clocked on each **rising edge of PPU address line A12** (filtered: A12 must have been low for a while).
When clocked: if the counter is 0 or a reload was requested, load the latch; otherwise decrement. If it is 0 after
that and IRQs are enabled, assert IRQ. With background at `$0000` and sprites at `$1000`, this happens once per
scanline around dot 260 (sprite fetches). Revisions differ for latch = 0.

SMB3 (from plan 03): mapper 4, 256 KiB PRG, 128 KiB CHR, 8 KiB PRG-RAM at `$6000` (no battery). It uses the IRQ to
split the screen between the playfield and the status bar; wrong IRQ timing shows up as a shaking or torn status bar.

## Scope

In: MMC3 banking, mirroring, PRG-RAM, the IRQ counter driven by A12 from the PPU's pattern fetch addresses, IRQ
delivery to the CPU.

Out: MMC6 specifics; the battery (SMB3 has none).

## Open decisions

- A12 source: notify the mapper on every PPU pattern-table fetch address (accurate, more calls per dot) vs a
  "scanline at dot 260 when rendering" shortcut (fast, breaks games with unusual pattern table setups).
  Recommendation: A12 notification, measure the cost, keep the shortcut as a documented fallback.
- MMC3 revision behaviour for latch = 0 (revision A vs B). Recommendation: revision B (most common), record it.

## Tasks

- [ ] Specify and test bank select/data for every register and both modes (PRG mode, CHR inversion).
- [ ] Specify and test mirroring and PRG-RAM protect.
- [ ] Specify and test the IRQ counter: reload, decrement, zero with IRQ enabled/disabled, acknowledge, latch = 0, A12
      filter (two rises close together clock once).
- [ ] Expose A12 from the PPU (plan 13/14 fetch addresses) to the mapper.
- [ ] Add `mmc3_test_2` to the manifest.
- [ ] Play SMB3 with the scripted headless input first (title → world map → 1-1), then interactively.

## Acceptance criteria

- [ ] `mmc3_test_2` ROMs `1-clocking`, `2-details`, `3-A12_clocking` and the revision ROM matching the chosen
      behaviour pass; `4-scanline_timing` and the other revision ROM are recorded with their result and reason.
- [ ] SMB3 boots to the title screen, the world map, and world 1-1.
- [ ] The status bar stays still while the playfield scrolls (checked with headless screenshots at several frames
      during scrolling, then by play).
- [ ] World 1-1 can be finished by playing interactively.
- [ ] 100% branch coverage on MMC3; rubocop clean.

## References

- MMC3 — https://www.nesdev.org/wiki/MMC3
- MMC3 IRQ and A12 — https://www.nesdev.org/wiki/MMC3#IRQ_Specifics
- TxROM board family — https://www.nesdev.org/wiki/TxROM
- PPU rendering (when pattern fetches happen) — https://www.nesdev.org/wiki/PPU_rendering
- `mmc3_test_2` — https://github.com/christopherpow/nes-test-roms (`mmc3_test_2/readme.txt`)
