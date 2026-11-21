# 22 — APU: pulse channels and frame counter

**Status:** done (2026-11-21)

**Depends on:** 12

## Goal

The APU skeleton: status/enable register, frame counter with its IRQ, the shared units (length counter, envelope,
sweep) and both pulse channels producing their 4-bit output per tick. No audio device yet. The frame IRQ is the first
periodic IRQ source, so the CPU interrupt timing gaps deferred by plans 07, 12 and 21 (IRQ polling point, the
`CLI`/`SEI`/`PLP` delay, the branch quirk, interrupt hijacking) are modelled here too, checked by `cpu_interrupts_v2`.

## Context

- Registers: `$4000-$4003` pulse 1, `$4004-$4007` pulse 2, `$4015` enable/status, `$4017` frame counter.
- Frame counter ([APU Frame Counter](https://www.nesdev.org/wiki/APU_Frame_Counter)): "The sequencer is clocked on
  every other CPU cycle, so 2 CPU cycles = 1 APU cycle". The NTSC table gives APU cycles labelled GET or PUT, the two
  halves of an APU cycle: mode 0 (4-step) 3728 PUT (quarter), 7456 PUT (quarter + half), 11185 PUT (quarter), 14914 GET
  (IRQ flag), 14914 PUT (quarter + half, IRQ flag), 0 (14915) GET (IRQ flag); mode 1 (5-step) 3728 PUT (quarter), 7456
  PUT (quarter + half), 11185 PUT (quarter), 14914 PUT (nothing), 18640 PUT (quarter + half), 0 (18641) GET; "In this
  mode, the interrupt flag is never set". In CPU cycles from the write's effect, `2 × apu` for GET and `2 × apu + 1`
  for PUT: 7457, 14913, 22371, 29828, 29829, 29830 (mode 0) and 7457, 14913, 22371, 29829, 37281, 37282 (mode 1), the
  same numbers as Mesen2's `ApuFrameCounter.h` (a cross-check, not a source). The 4-step flag is set "every 29830 CPU
  cycles".
- `$4017` write: "Writing to this register resets the counter to 0"; "If the write occurs during an APU cycle, the
  effects occur 3 CPU cycles after the write cycle, and if the write occurs between APU cycles, the effects occurs 4
  CPU cycles after the write cycle"; with bit 7 set "both Quarter frame and Half frame clocks are also generated", and
  the APU page: "Generate all clocks immediately as well if the M bit was written set". The flag "can be acknowledged
  (cleared) by writing to $4017 with interrupt inhibit flag set (I bit)".
- `$4015` read ([APU](https://www.nesdev.org/wiki/APU)): `IF-D NT21` (DMC IRQ, frame interrupt, DMC active, length
  counters > 0). "Reading this register clears the frame counter interrupt flag (but not the DMC interrupt flag)"; "If
  an interrupt flag was set at the same moment of the read, it will read back as 1 but it will not be cleared". "This
  register is internal to the CPU and so the external CPU data bus is disconnected when reading it", so the read "does
  not affect open bus", and bit 5 comes from open bus.
- `$4015` write `---D NT21`: clearing a channel's bit forces its length counter to 0 and keeps it there; "Writing to
  this register also clears the DMC sample-end interrupt flag" (plan 23).
- Length counter ([APU Length Counter](https://www.nesdev.org/wiki/APU_Length_Counter)): table 10, 254, 20, 2, 40, 4,
  80, 6, 160, 8, 60, 10, 14, 12, 26, 14, 12, 16, 24, 18, 48, 20, 96, 22, 192, 24, 72, 26, 16, 28, 32, 30; loaded "if
  the enabled flag is set"; clocked by the half frame unless 0 or halted (bit 5 of `$4000`/`$4004`); "When the enabled
  bit is cleared (via $4015), the length counter is forced to 0 and cannot be changed until enabled is set again".
- Envelope ([APU Envelope](https://www.nesdev.org/wiki/APU_Envelope)): start flag (set by `$4003`/`$4007`), divider
  (period V + 1), decay level 15 down to 0, looping when the loop flag (bit 5) is set; output V when the constant
  volume flag (bit 4) is set, the decay level otherwise; "the decay level will still be updated".
- Pulse ([APU Pulse](https://www.nesdev.org/wiki/APU_Pulse)): 11-bit timer "updated every APU cycles (i.e., every second
  CPU cycles)", clocking the sequencer when it reloads; duty sequences 0 1 0 0 0 0 0 0, 0 1 1 0 0 0 0 0, 0 1 1 1 1 0 0
  0, 1 0 0 1 1 1 1 1, read "in the order 0, 7, 6, 5, 4, 3, 2, 1"; a `$4003`/`$4007` write "resets the sequencer index
  ... restart envelope" and reloads the length counter. The output is 0 when the sequencer outputs 0, the sweep mutes,
  the length counter is 0 or the timer is < 8; the envelope's volume otherwise.
- Sweep (same page): `EPPP NSSS`; a write sets the reload flag; target = period + (period >> S), negated with ones'
  complement on pulse 1 ("Making 20 negative produces a change amount of −21") and two's complement on pulse 2; "If the
  target period is larger than $7FF, it silences the channel", and "This muting happens regardless of the state of the
  sweep unit". On a half frame: if the divider is 0, enabled, the shift is non-zero and the channel is not muted, the
  period becomes the target; if the divider is 0 or the reload flag set, the divider reloads from P and the flag
  clears, otherwise it decrements.
- Power-up and reset ([CPU power up state](https://www.nesdev.org/wiki/CPU_power_up_state)): `$4015` 0 "(all channels
  disabled)" at power and after reset; `$4017` 0 "(frame IRQ enabled)" at power, "unchanged" after reset; pulse
  registers 0 at power.
- CPU interrupts ([CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts)): "it's really the status of the
  interrupt lines at the end of the second-to-last cycle that matters"; the IRQ input "is connected to a level
  detector"; "The CLI, SEI, and PLP instructions on the other hand change the I flag after polling for interrupts", so
  "executing CLI will execute the next instruction before the CPU invokes the IRQ handler", while an RTI that clears I
  lets a pending IRQ in "immediately after RTI finishes executing"; branches poll "before the second CPU cycle (the
  operand fetch)", not before the third on a taken branch, and on a page-crossing taken branch also before the PCH
  fixup cycle; "if NMI is asserted during the first four ticks of a BRK instruction, the BRK instruction will execute
  normally at first", the vector being picked after tick 4, and "an NMI can hijack an IRQ".

## Scope

In: everything above; the APU caught up by the console once per step and before its register accesses; the frame IRQ
wired to the CPU IRQ line with its cycle; the IRQ polling point, the `CLI`/`SEI`/`PLP` delay, the branch polling quirk
and interrupt hijacking in the CPU.

Out: triangle, noise, DMC, mixer (plan 23); audio output (plan 24).

## Decisions

1. **The whole CPU interrupt timing is in scope, hijacking included.** The IRQ line carries the cycle it was asserted
   on and is polled at the same point as the NMI edge (plan 12, decision 2); `CLI`, `SEI` and `PLP` change I after the
   poll; a taken branch that does not cross a page polls one cycle earlier, for NMI and IRQ alike (the page says
   "interrupts"); BRK and the IRQ sequence pick their vector after tick 4, once the PPU caught up to it, so an NMI edge
   by then hijacks them. Reason: the frame IRQ makes every one of them testable (`cpu_interrupts_v2` 1-5), and they all
   rest on the same cycle stamps.
2. **`$4015` and open bus: the bus does not store what the `apu_registers:` slot returns.** `$4000-$4015` are the
   2A03's internal registers; `$4000-$4013` are open bus already (the slot returns `data_bus`, so storing it changes
   nothing), and `$4015` must leave the bus as it was. The APU keeps bit 5 from `data_bus`. Zero cost: the assignment
   moves into each branch of `CpuBus#read`. Rejected: a dedicated `$4015` read path (one more comparison).
3. **The APU is caught up like the PPU.** `Apu#catch_up(cpu_cycle)` advances one CPU cycle at a time (frame counter
   every cycle, pulse timers every other one). `Console#step` calls it after each step; the APU gets the CPU as its
   clock (`cpu=`, as MMC1) and catches itself up to `cycles - 1`, the access cycle, before every register read or
   write. Rejected: catching up only after each step, which puts `$4015` reads and `$4017` writes up to an instruction
   off.
4. **Reset clears `$4015` and the frame interrupt flag, and writes `$4017`'s last value again**; power-up acts as a
   `$00` write to `$4017`. First decided as "reset leaves the frame counter alone" from the CPU power up state page's
   "unchanged"; the review found the frame flag surviving a reset, and the readme of blargg's `apu_reset` (written
   against the console) settles both: "At power and reset, IRQ flag is clear" and "At reset, same as above, except last
   value written to $4017 is written again, rather than $00". The "9-12 clock delay" it also gives is not modelled
   (Known gaps). `apu_reset` joins the manifest: 5 of its 6 ROMs pass; `works_immediately` needs the DMC (plan 23).
5. **GET cycles are the even CPU cycles**, the convention `CpuBus::OamDma` already follows (plan 11, decision 3): no
   page says which parity is which. A `$4017` write on an odd cycle takes effect 3 CPU cycles later, one on an even
   cycle 4. `apu_test` passes with either pairing; `cpu_interrupts_v2/4-irq_and_dma` only with this one (the three
   other combinations of DMA and APU parity were tried; the IRQ at +526 lands one instruction late).
6. **`Cpu#assert_irq(source, cycle)` and `Cpu#release_irq(source, cycle)`**: a source tells the CPU cycle it pulled or
   let go of the line. MMC3 passes its `A12Watcher` M2 cycle when asserting and `Cpu#access_cycle` (the instruction's
   last cycle) when `$E000` releases; the frame interrupt its cycles; the DMC its own (plan 23). An IRQ released on or
   after the poll cycle is still taken once. `InterruptLines` was split into `Cpu::NmiDetector`, `Cpu::IrqLine` and
   the arbiter: its specification had grown past 30 leaves.
7. **A `$4015` read clears the frame interrupt flag even on the cycle it was set.** The APU page says "If an interrupt
   flag was set at the same moment of the read, it will read back as 1 but it will not be cleared", but
   `apu_test/6-irq_flag_timing` reads on the cycle of the third set and requires the flag not to be seen again (#5,
   "Flag last set too late"); the test was written against the console. Recorded in Known gaps.
8. **The triangle's and the noise's length counters come now** (`Apu::Triangle`, `Apu::Noise`: `$4008` bit 7 and
   `$400B`, `$400C` bit 5 and `$400F`, `$4015` bits 2 and 3): `apu_test` 1, 2 and 5 test the four main channels and
   fail on channel 2 without them. The rest of both channels stays in plan 23.
9. **Interrupt sequences and DMA stalls do not poll.** "The interrupt sequences themselves do not perform interrupt
   polling, meaning at least one instruction from the interrupt handler will execute before another interrupt is
   serviced" (CPU interrupts, "Detailed interrupt behavior"): `cpu_interrupts_v2` 2 and 3 showed the NMI one
   instruction early without it. A DMA halts the CPU after its instruction polled, so the next poll looks back past
   the stall: `cpu_interrupts_v2/4-irq_and_dma`.

## Tasks

- [x] `Cpu::InterruptLines`: IRQ asserted with its cycle, polled as the NMI; I held for one poll after `CLI`/`SEI`/`PLP`;
      the early poll of a taken non-page-crossing branch; the vector after tick 4 for hijacking (split into a
      `Cpu::IrqLine` if the tree says so).
- [x] Instructions: `CLI`, `SEI`, `PLP` tell the lines the I before them; a taken branch without a page cross tells
      the early poll.
- [x] `Cpu::Interrupts`: BRK and IRQ catch the PPU up to tick 4 (an `interrupt_sync` collaborator, the console's
      `PpuRegisterSync`) and ask the lines for the vector.
- [x] MMC3 asserts its IRQ with its cycle.
- [x] Specify and test the length counter (table load, halt, disable via `$4015`), envelope, sweep (both negate modes,
      muting), pulse (duty sequencer, timer, output).
- [x] Specify and test the frame interrupt (flag, inhibit, cleared by a `$4015` read, even on the cycle it is set:
      decision 7) and the frame counter (both modes, write delay, immediate clocks in mode 1, reset).
- [x] `Apu`: register decoding, `$4015` status and enable, catch-up, power-up and reset; `CpuBus` leaves the data bus
      alone on the APU slot's reads; `Console` wires and catches up the APU.
- [x] Add `apu_test` 1-6, `instr_timing` 1-2 and `instr_misc/04-dummy_reads_apu` to the manifest; rerun the
      `cpu_interrupts_v2` singles and `mmc3_test_2/4-scanline_timing`.
- [x] Update `docs/architecture.md`, `docs/GLOSSARY.md`, `docs/test-roms.md`; plans 23 and 25.

## Acceptance criteria

- [x] `apu_test` `1-len_ctr`, `2-len_table` and `3-irq_flag` pass; `4-jitter`, `5-len_timing`, `6-irq_flag_timing`
      results recorded with reasons.
- [x] `cpu_interrupts_v2` `1-cli_latency` passes; 2-5 pass or their failures are recorded with the reason; the Known
      gaps rows they cover (polling point, `CLI`/`SEI`/`PLP` delay, hijacking, MMC3 IRQ timing with
      `mmc3_test_2/4-scanline_timing` rerun) are updated.
- [x] `instr_misc/04-dummy_reads_apu` and `instr_timing` (1 and 2) results recorded.
- [x] Every test ROM that passed before still passes (`SLOW=1 bundle exec rake`).
- [x] 100% branch coverage on APU code and on the CPU code changed; rubocop clean.

## What was done

- The interrupt lines: `Cpu::NmiDetector` (the edge, extracted), `Cpu::IrqLine` (the wired-OR level, each assert and
  release stamped with its cycle) and `Cpu::InterruptLines` as the arbiter of the poll: the I `CLI`/`SEI`/`PLP` leave
  for it, the early poll of a taken branch without a page cross, no poll during a DMA stall nor after an interrupt
  sequence, hijacking of BRK and IRQ by an NMI after tick 4 (the CPU's `interrupt_sync`, the console's register sync),
  and a reset that forgets them. `Cpu#access_cycle` names the instruction's access cycle (`PpuRegisterSync` reuses
  it); MMC3 stamps its IRQ with the A12 rise's M2 cycle.
- The APU: `Apu` (register decoder, `$4015`, catch-up per CPU cycle, reset), two `Apu::Pulse`s (`Timer`,
  `DutySequencer`, `Envelope`, `Sweep`, `LengthCounter`), `Apu::FrameCounter` (constant tables per mode, the `$4017`
  write delay by parity) and `Apu::FrameInterrupt`, plus the triangle's and noise's length counters
  (`Apu::Triangle`, `Apu::Noise`, decision 8). `CpuBus` leaves the data bus alone on the APU slot's reads; `Console`
  wires the APU and catches it up after each step.
- Test ROMs, all slow examples: `apu_test` 1-6, `apu_reset` (but `works_immediately`, plan 23), `cpu_interrupts_v2`
  1-5 and its multi-test build, `instr_timing` 1-2, `instr_misc/04-dummy_reads_apu`. `mmc3_test_2/4-scanline_timing`
  still fails #2 (Known gaps: MMC3 IRQ timing). Every ROM that passed before still passes, SMB3's example included.
- `docs/architecture.md` (APU section, Interrupt timing, the slot's open bus, clock model, layout, Known gaps,
  decisions 57-63), `docs/GLOSSARY.md` (APU cycle, duty cycle, envelope, frame counter, hijacking, length counter,
  quarter/half frame, sweep), `docs/test-roms.md`; plans 23 and 25 inherit the catch-up, the IRQ stamps, the DMC's
  share of `$4015` and the review's deferred points.
- Independent review: applied the reset of the poll's exceptions and of the frame flag and `$4017` (decision 4, from
  `apu_reset`'s readme), `Cpu#access_cycle` reused, the length table index decoded by `LengthCounter`, named register
  numbers, the branch's `page-crossed` tag, an unsourced comment dropped, two spec leaves that repeated causes, long
  comment lines. Deferred to plan 23: a channel table in `Apu#cpu_write` and `IrqLine`'s single assert/release window.
- The raylib window spec crashes this environment's Ruby on `CloseWindow`, on `master` too; the suite ran with
  `--tag '~frontend_library'`.

## References

- APU — https://www.nesdev.org/wiki/APU
- APU Frame Counter — https://www.nesdev.org/wiki/APU_Frame_Counter
- APU Length Counter — https://www.nesdev.org/wiki/APU_Length_Counter
- APU Envelope — https://www.nesdev.org/wiki/APU_Envelope
- APU Sweep — https://www.nesdev.org/wiki/APU_Sweep (served by the APU Pulse page)
- APU Pulse — https://www.nesdev.org/wiki/APU_Pulse
- CPU power up state — https://www.nesdev.org/wiki/CPU_power_up_state
- CPU interrupts — https://www.nesdev.org/wiki/CPU_interrupts
- DMA (GET/PUT halves of the APU clock) — https://www.nesdev.org/wiki/DMA
- Mesen2 `Core/NES/APU/ApuFrameCounter.h` (cross-check of the CPU-cycle table) — https://github.com/SourMesen/Mesen2
- `apu_test`, `instr_timing`, `instr_misc`, `cpu_interrupts_v2` readmes — https://github.com/christopherpow/nes-test-roms
