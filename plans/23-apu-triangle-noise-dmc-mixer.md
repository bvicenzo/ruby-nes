# 23 — APU: triangle, noise, DMC and mixer

**Depends on:** 22

## Goal

The remaining channels and the mixer, so the APU produces one analog-like output value per CPU cycle.

## Context

- Triangle (`$4008-$400B`): timer clocked every CPU cycle, 32-step sequence, linear counter (quarter frame) and length
  counter; ultrasonic periods (< 2) are commonly silenced by emulators to avoid a pop.
- Noise (`$400C-$400F`): 15-bit LFSR, short mode (feedback from bit 6 instead of bit 1), NTSC period table, envelope,
  length counter.
- DMC (`$4010-$4013`): plays 1-bit delta samples fetched from CPU memory (`$C000 + A*64`, length `L*16 + 1`), rate
  table, loop flag, IRQ on end; each fetch **stalls the CPU** (1–4 cycles) and steals the bus.
- Mixer: non-linear formulas, `pulse_out = 95.88 / (8128 / (p1 + p2) + 100)` and
  `tnd_out = 159.79 / (1 / (t/8227 + n/12241 + d/22638) + 100)`, usually implemented with lookup tables.

## Scope

In: the three channels, the DMC memory reader with CPU stall, DMC IRQ, the mixer with lookup tables.

Out: resampling and the audio device (plan 24); expansion audio (MMC5, VRC6, … — none needed for SMB3).

## Open decisions

- DMC stall precision: fixed 4 cycles (simple) vs the documented 1–4 depending on the CPU cycle being read/write.
  Recommendation: start fixed, refine if `apu_test`/`dmc` tests require it.

## Tasks

- [ ] Specify and test triangle (linear counter reload flag, control flag, sequencer, ultrasonic silence decision).
- [ ] Specify and test noise (LFSR both modes, period table).
- [ ] Specify and test DMC (address wrap from `$FFFF` to `$8000`, loop, IRQ, stall reported to the CPU).
- [ ] Specify and test the mixer tables against the formulas (boundary values: all silent, maxima).

## Acceptance criteria

- [ ] `apu_test` `7-dmc_basics` and `8-dmc_rates` pass.
- [ ] Mixer output for silent channels is exactly 0 and the maxima match the formulas within float tolerance.
- [ ] 100% branch coverage on APU code; rubocop clean.

## References

- APU Triangle — https://www.nesdev.org/wiki/APU_Triangle
- APU Noise — https://www.nesdev.org/wiki/APU_Noise
- APU DMC — https://www.nesdev.org/wiki/APU_DMC
- APU Mixer — https://www.nesdev.org/wiki/APU_Mixer
- DMA (DMC stalls) — https://www.nesdev.org/wiki/DMA
