# 12 — PPU timing, VBlank/NMI and the console loop

**Depends on:** 07, 11

## Goal

Make time pass: the PPU dot/scanline counters, the VBlank flag, NMI generation, the odd-frame skipped dot, and a
`Console` that runs CPU and PPU together frame by frame. Then run blargg's CPU instruction tests, which need VBlank.

## Context

NTSC frame: 262 scanlines × 341 dots.

| Scanlines | Phase |
|---|---|
| 0–239 | visible |
| 240 | post-render (idle) |
| 241–260 | VBlank; flag set at scanline 241 dot 1 (NMI here if enabled) |
| 261 (−1) | pre-render; VBlank, sprite 0 hit and overflow cleared at dot 1 |

On odd frames with rendering enabled, the pre-render line is one dot shorter (dot 339 → next frame dot 0). Enabling
NMI in PPUCTRL while the VBlank flag is set triggers an NMI immediately. Reading `$2002` right at the moment VBlank is
set suppresses that frame's flag/NMI (race documented on the NMI page).

The console loop (clock model chosen in plan 01): step the CPU, advance the PPU 3 dots per CPU cycle, deliver NMI to
the CPU, stop at the end of each frame.

## Scope

In: PPU `tick`, frame counter and frame-complete signal, VBlank/NMI, odd-frame skip, `Console#run_frame`,
`Console#reset`, the blargg result reader (`$6000` status, `$6001-$6003` signature, `$6004+` text) as a test helper.

Out: pixels (plan 13).

## Open decisions

- Whether the suppression/race cases are modelled now. With instruction-level catch-up they likely cannot be exact;
  recommendation: model what the clock model allows and document the rest.
- If `ppu_vbl_nmi` timing tests reveal the catch-up model is insufficient for later goals (SMB3, plan 21), switch to
  per-bus-access ticking here, before rendering is built on top. Decide with the numbers from the test run.

## Tasks

- [ ] Specify and test the counters (wrap, odd-frame skip with rendering on/off), VBlank set/clear, NMI edge.
- [ ] Specify and test `Console#run_frame` (returns after exactly one frame; CPU cycles per frame within the documented
      29 780/29 781).
- [ ] Blargg result reader in `spec/support/`, with specs on synthetic memory.
- [ ] Add `instr_test-v5` and `ppu_vbl_nmi` to the test ROM manifest (check each ROM's mapper with plan 03's loader;
      ROMs whose mapper is not implemented yet move to the acceptance of that mapper's plan).

## Acceptance criteria

- [ ] All `instr_test-v5` single ROMs whose mapper is implemented report "Passed".
- [ ] `ppu_vbl_nmi` `01-vbl_basics` and `04-nmi_control` pass; the result of every other ROM in the suite is recorded
      in `docs/test-roms.md` with the reason for each failure.
- [ ] The nestest trace `PPU:` column now matches too (extend plan 08's comparison).
- [ ] 100% branch coverage on the timing code; rubocop clean.

## References

- PPU frame timing — https://www.nesdev.org/wiki/PPU_frame_timing
- PPU rendering (scanline timeline) — https://www.nesdev.org/wiki/PPU_rendering
- NMI — https://www.nesdev.org/wiki/NMI
- PPU power up state — https://www.nesdev.org/wiki/PPU_power_up_state
- Cycle reference chart — https://www.nesdev.org/wiki/Cycle_reference_chart
- `instr_test-v5`, `ppu_vbl_nmi` — https://github.com/christopherpow/nes-test-roms (each suite's `readme.txt`)
