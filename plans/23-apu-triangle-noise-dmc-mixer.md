# 23 — APU: triangle, noise, DMC and mixer

**Status:** done (2026-11-21)

**Depends on:** 22

## Goal

The remaining channels and the mixer, so the APU produces one analog-like output value per CPU cycle.

## Context

- Timers ([APU](https://www.nesdev.org/wiki/APU), Glossary): "The triangle's timer is clocked on every CPU cycle", the
  pulse, noise and DMC timers "only on every second CPU cycle and thus produce only even periods". The noise and DMC
  tables are given in CPU cycles (all even), so `Apu::Timer`, ticked every APU cycle, takes half the table entry,
  minus 1.
- Triangle ([APU Triangle](https://www.nesdev.org/wiki/APU_Triangle)): `$4008` `CRRR RRRR`, bit 7 "Linear counter
  control flag and length counter halt flag", bits 6-0 the reload value; `$400A` timer low; `$400B` length index and
  timer high, "Writing to this register sets linear counter reload flag too". On a quarter frame: "If the linear counter
  reload flag is set, the counter is reloaded with the counter reload value, otherwise, if the counter is non-zero, it
  is decremented", then "If the counter control flag (C bit) is clear, the reload flag is cleared". "The sequencer is
  clocked by the timer as long as both the linear counter and the length counter are nonzero"; sequence 15, 14, …, 0, 0,
  1, …, 15. Ultrasonic periods: "Due to external filtering, ultrasonic frequencies are averaged into constant output at
  roughly half amplitude".
- Noise ([APU Noise](https://www.nesdev.org/wiki/APU_Noise)): `$400C` `--LC VVVV` (envelope, length halt); `$400E`
  `M--- PPPP`; `$400F` length index, "also restarts envelope". NTSC periods in CPU cycles: 4, 8, 16, 32, 64, 96, 128,
  160, 202, 254, 380, 508, 762, 1016, 2034, 4068. "On power-up, the shift register is loaded with the value 1. Reset
  does not affect shift register." "Feedback is calculated as the exclusive-OR of bit 0 and one other bit: bit 6 if
  periodic noise mode (M bit) is set, otherwise bit 1"; the register shifts right and bit 14 gets the feedback. The
  mixer gets the envelope's volume "except when bit 0 of the shift register is set, or the length counter is zero".
- DMC ([APU DMC](https://www.nesdev.org/wiki/APU_DMC)): `$4010` `IL-- RRRR` (IRQ enable, loop, rate index), `$4011`
  `-DDD DDDD` direct load, `$4012` sample address `$C000 + A × 64`, `$4013` sample length `L × 16 + 1` bytes. NTSC
  rates in CPU cycles: 428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54. The memory reader
  fetches "whenever the sample buffer is empty and the bytes-remaining counter isn't 0"; the address "If it exceeds
  $FFFF, it's wrapped around $8000"; at the end of the sample the loop flag restarts it, otherwise the IRQ flag is set
  if enabled; the flag is cleared "by writing any value to $4015 or by clearing the sample-end interrupt flag (I bit)
  in $4010". The output unit shifts an 8-bit register: bit 0 = 1 raises the level by 2 if below 126, 0 lowers it by 2
  if above 1; after eight bits a new byte comes from the buffer, or the unit stays silent for eight more clocks. The
  level "is sent to the mixer regardless the channel is enabled or not" (APU: "always outputs the current value of
  its counter").
- `$4015` and the DMC ([APU](https://www.nesdev.org/wiki/APU)): write bit 4 clear, "the bytes-remaining counter is set
  to 0"; set, "the DMC sample will be restarted only if its bytes-remaining counter is 0"; "Writing to this register
  also clears the DMC sample-end interrupt flag regardless of the written value". Read bit 4 "will return 1 if the
  remaining sample byte is non-zero", bit 7 "DMC sample-end IRQ asserted"; reading does not clear the DMC flag.
- DMC DMA ([DMA](https://www.nesdev.org/wiki/DMA)): "DMC DMA halts the CPU, performs a dummy cycle and an optional
  alignment cycle, and then gets once, taking 3 or 4 cycles"; "Load DMAs take 3 cycles and reload DMAs take 4 unless
  the halt is delayed by an odd number of cycles". Load DMAs follow a `$4015` write and "are scheduled to halt the CPU
  on a get cycle during the 2nd APU cycle after the write (that is, the 3rd or 4th CPU cycle)"; reload DMAs follow the
  buffer emptying. "DMA can only halt on CPU read cycles"; "DMC DMA occurring during OAM DMA will cost only 2 cycles".
- Reset ([CPU power up state](https://www.nesdev.org/wiki/CPU_power_up_state)): after reset "Triangle phase … 0 (output
  = 15)", "[$4011] &= 1", `$4010`, `$4012`, `$4013` unchanged, `$4015` 0. That page gives the noise LFSR at power as
  "$0000 (all 0s, first clock shifts in a 1)"; the APU Noise page says 1 (decision 6).
- Mixer ([APU Mixer](https://www.nesdev.org/wiki/APU_Mixer)): exact formulas `pulse_out = 95.88 / ((8128 / (pulse1 +
  pulse2)) + 100)`, `tnd_out = 159.79 / (1 / ((triangle / 8227) + (noise / 12241) + (dmc / 22638)) + 100)`; "When the
  values for one of the groups are all zero, the result for that group should be treated as zero"; lookup tables
  `pulse_table[n] = 95.52 / (8128.0 / n + 100)` (31 entries, index `pulse1 + pulse2`) and `tnd_table[n] = 163.67 /
  (24329.0 / n + 100)` (203 entries, index `3 * triangle + 2 * noise + dmc`).

## Scope

In: the three channels, the DMC memory reader with CPU stall, DMC IRQ, the mixer with lookup tables, `Apu#output`.

Out: resampling and the audio device (plan 24); expansion audio (MMC5, VRC6, … — none needed for SMB3); the DMC's
extra reads on `$4016`/`$4017`/`$2007` (Known gaps).

From plan 11: stalls reach the CPU through `CpuBus#take_stall_cycles(halt_cycle)`, which `Cpu#step` adds after each
instruction; OAM DMA (`CpuBus::OamDma`) keeps that channel. The DMC pushes its stalls instead (decision 1).

From plan 22: the APU is caught up like the PPU (`Apu#catch_up(cpu_cycle)` after each step and to `cycles - 1` before
each register access, decision 3), with GET cycles on even CPU cycles (decision 5); the new channels join that loop.
The DMC IRQ is another wired-OR source asserted and released with its cycle (decision 6). `$4015` already reads
`IF-D NT21` with bit 5 from open bus (decision 2). `Apu::Triangle` and `Apu::Noise` exist with their length counters
only (decision 8); this plan completes them. Left by plan 22's review: `Apu#cpu_write` decodes the channels with a
growing `if`/`elsif` chain, to be replaced by a preallocated channel array indexed by address bits 4-2;
`Cpu::IrqLine` keeps only the latest assert and release cycles (decision 7). `apu_reset/works_immediately` fails "At
power, writes should work immediately" until the DMC exists.

## Decisions

1. **The DMC pushes its stall to the CPU: `Cpu#halt(stall_cycles)`**, called on the cycle the fetch happens; it adds
   the cycles and tells the interrupt lines to poll back past them (plan 22, decision 9). `Cpu#add_stall_cycles` uses
   it for OAM DMA's stall, which still comes from `CpuBus#take_stall_cycles`. Reason: no query per step when nothing
   fetches, and the stall lands when it happens (pulled, a fetch in the post-step catch-up would be charged after the
   next step). Moving OAM DMA to the same push is plan 25's (it would re-open plan 22's calibration). Changes
   architecture decision 20.
2. **A load fetch (from a `$4015` write) stalls 3 cycles, a reload fetch 4**, the DMA page's rule. Not modelled: a halt
   delayed by write cycles, and the 2-cycle cost of a DMC fetch during OAM DMA (Known gaps). Rejected: a fixed 4
   (the page gives both numbers at no extra cost).
3. **The load fetch happens on the `$4015` write**, not on the "3rd or 4th CPU cycle" after it, as OAM DMA copies at
   once. `7-dmc_basics` #19 reads `$4015` 4 cycles after the write and sees the same either way. Known gap.
4. **Ultrasonic triangle periods are played as the hardware plays them**: no silencing of periods below 2. The page
   says the external filter averages them to about half amplitude; plan 24's filters and resampler decide whether a
   workaround is needed once heard. No branch on the hot path.
5. **The mixer uses the page's lookup tables** (31 and 203 `Float` entries, constants 95.52 and 163.67), computed once
   into frozen arrays. Silence is exactly 0.0; at the maxima the tables stay within 0.5% of the exact formulas
   (0.2575 vs 0.2585 for the pulses, 0.7425 vs 0.7415 for triangle/noise/DMC).
6. **The noise shift register starts at 1** (APU Noise), against CPU power up state's "$0000 (all 0s, first clock
   shifts in a 1)": the two differ by one step. Reset leaves it alone (both pages agree).
7. **`Cpu::IrqLine` keeps its single assert/release window.** A poll that looks back past a DMC stall (3-4 cycles)
   would miss only a release and re-assert within those cycles; recorded in Known gaps, reopened if a ROM needs it.
8. **`Apu#output` mixes on demand**; accumulating one value per CPU cycle for the resampler is plan 24's, in the
   catch-up.
9. **The DMC output unit starts silent, eight timer clocks from its first byte**: no page gives its state at power (the
   APU DMC page has no power-up section, and CPU power up state gives only `$4011`), so it is a convention, found by
   the review.

## Tasks

- [x] `Cpu#halt(stall_cycles)` and `Cpu::InterruptLines::DMC_IRQ`.
- [x] Specify and test the triangle: `Apu::LinearCounter` (reload flag, control flag), `Apu::TriangleSequencer`
      (32 steps, reset phase), `Apu::Triangle` (registers, timer every CPU cycle, gated sequencer, output, reset).
- [x] Specify and test the noise: `Apu::NoiseShiftRegister` (both modes), `Apu::Noise` (period table, envelope,
      output).
- [x] Specify and test the DMC: `Apu::Dmc::OutputUnit` (shift register, silence, level clamps, direct load),
      `Apu::Dmc::MemoryReader` (address wrap from `$FFFF` to `$8000`, loop, IRQ, stall reported to the CPU),
      `Apu::Dmc` (registers, rate table, `$4015` enable, status, reset).
- [x] Specify and test `Apu::Mixer` against the table formulas (all silent, maxima).
- [x] `Apu`: channel table in `cpu_write`, `$4015` bits 4 and 7, the new channels in the catch-up and the frame
      clocks, `output`, `memory=`; `Console` wires the bus to the APU.
- [x] Add `apu_test` 7-8 to the manifest; run them and `apu_reset/works_immediately`.
- [x] Update `docs/architecture.md`, `docs/GLOSSARY.md`, `docs/test-roms.md`; plans 24 and 25.

## Acceptance criteria

- [x] `apu_test` `7-dmc_basics` and `8-dmc_rates` pass.
- [x] `apu_reset/works_immediately` passes, or its failure is recorded with the reason.
- [x] Mixer output for silent channels is exactly 0; the entries reached by one channel alone (1, 2, 3) and the
      maxima (30, 202) match the page's table formulas, which build every entry, and the maxima are within 0.5% of the
      exact formulas.
- [x] Every test ROM that passed before still passes (`SLOW=1 bundle exec rake`), SMB3's example included.
- [x] 100% branch coverage on APU code and on the CPU code changed; rubocop clean.

## What was done

- The CPU: `Cpu#halt(stall_cycles)`, the push a DMA uses to stall the CPU (OAM DMA's pulled stall goes through it
  too), and the `DMC_IRQ` source.
- The triangle: `Apu::LinearCounter`, `Apu::TriangleSequencer` and `Apu::Triangle`, its timer ticked every CPU cycle.
  The noise: `Apu::NoiseShiftRegister` and `Apu::Noise`. The DMC: `Apu::Dmc` with `Dmc::Sample` (address and
  bytes-remaining counters), `Dmc::MemoryReader` (the sample buffer, filled by DMA with a 3- or 4-cycle halt) and
  `Dmc::OutputUnit`. `Apu::Mixer` with the page's lookup tables; `Apu#output`.
- Reuse: `Apu::FrameInterrupt` became `Apu::InterruptFlag(source:)`, shared by the frame counter and the DMC;
  `Apu::Timer` gained `write_period_low`/`write_period_high` (shared by the pulse and the triangle), a `period:` keyword
  and `Timer.reload_for(cpu_cycles)` (the noise and DMC tables). `Apu#cpu_write` reaches the channels through a
  constant table, plan 22's deferred point.
- `Apu`: `$4015` bits 4 and 7, the DMC on `$4015` writes, the new timers in the catch-up, the noise and the linear
  counter on quarter frames, `memory=`, reset of the triangle's phase and the DMC's level; a register access catches
  up past a DMC stall. `Console` wires the bus to the APU, and `Console#step` returns the CPU's advance, stalls
  included.
- Test ROMs: `apu_test` 7-8 joined the manifest; they and `apu_reset/works_immediately` pass. Every ROM that passed
  before still passes, SMB3's example included.
- `docs/architecture.md` (APU section, components, clock model, layout, Known gaps, decisions 64-67),
  `docs/GLOSSARY.md` (DMC, LFSR, linear counter, mixer, sample buffer, stall), `docs/test-roms.md`; plans 24 and 25.
- Independent review: applied the catch-up past a DMC stall before register accesses, the noise timer's power-up
  period, `Console#step` counting stalls from the APU's catch-up, the output unit's power-up state as a convention
  (decision 9), the shift register's named steps, `Timer.reload_for`, `Bits` reuse, comments and line lengths.
  Deferred to plan 25: the DMC's cycle kept for its timer's `step`.
- The raylib window spec crashes this environment's Ruby on `CloseWindow` (as in plan 22); the suite ran with
  `--tag '~frontend_library'`.

## References

- APU — https://www.nesdev.org/wiki/APU
- APU Triangle — https://www.nesdev.org/wiki/APU_Triangle
- APU Noise — https://www.nesdev.org/wiki/APU_Noise
- APU DMC — https://www.nesdev.org/wiki/APU_DMC
- APU Mixer — https://www.nesdev.org/wiki/APU_Mixer
- DMA (DMC stalls) — https://www.nesdev.org/wiki/DMA
- CPU power up state — https://www.nesdev.org/wiki/CPU_power_up_state
- `apu_test` and `apu_reset` readmes and sources (`7-dmc_basics.s`, `8-dmc_rates.s`, `works_immediately.s`) —
  https://github.com/christopherpow/nes-test-roms
