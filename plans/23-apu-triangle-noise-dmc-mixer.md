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

From plan 11: stalls reach the CPU through `CpuBus#take_stall_cycles(halt_cycle)` (the CPU cycle the halt falls on, one
after the write), which `Cpu#step` adds after each instruction; OAM DMA (`CpuBus::OamDma`) already reports there, with
get cycles being the even CPU cycles counted from `Cpu.new` (a convention, plan 11 decision 3). The DMC reports through
the same channel; the DMA page's interaction of DMC and OAM DMA is decided here.

From plan 22: the APU is caught up like the PPU (`Apu#catch_up(cpu_cycle)` after each step and to `cycles - 1` before
each register access, decision 3), with GET cycles on even CPU cycles (decision 5); the new channels join that loop.
The DMC IRQ is another wired-OR source asserted and released with its cycle, `Cpu#assert_irq(source, cycle)` and
`#release_irq(source, cycle)` (decision 6). `$4015` already reads `IF-D NT21` with bit 5 from open bus and leaves the
bus untouched (decision 2), with the triangle's and noise's length counters in bits 2 and 3: `Apu::Triangle` and
`Apu::Noise` exist with their length counters only (decision 8), and this plan completes them. The DMC fills bits 7
and 4, and the write's DMC bit and DMC IRQ clear come here. A DMA stall reported through `take_stall_cycles` already
keeps the CPU from polling during it (decision 9), so the DMC's stalls get that for free.

Left to this plan by plan 22's review: `Apu#cpu_write` decodes the channels with a growing `if`/`elsif` chain; with the
DMC at `$4010-$4013`, a preallocated array of the four channels indexed by address bits 3-2 is cheaper and flatter.
`Cpu::IrqLine` keeps only the latest assert and release cycles, so a poll that looks back past a DMA stall misses an
assertion released and asserted again within that stall; DMC stalls make that reachable, so decide whether to keep a
history. `apu_reset/works_immediately` (in the manifest since plan 22) fails "At power, writes should work immediately"
until the DMC and the triangle's linear counter exist.

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
- [ ] `apu_reset/works_immediately` passes, or its failure is recorded with the reason.
- [ ] Mixer output for silent channels is exactly 0 and the maxima match the formulas within float tolerance.
- [ ] 100% branch coverage on APU code; rubocop clean.

## References

- APU Triangle — https://www.nesdev.org/wiki/APU_Triangle
- APU Noise — https://www.nesdev.org/wiki/APU_Noise
- APU DMC — https://www.nesdev.org/wiki/APU_DMC
- APU Mixer — https://www.nesdev.org/wiki/APU_Mixer
- DMA (DMC stalls) — https://www.nesdev.org/wiki/DMA
