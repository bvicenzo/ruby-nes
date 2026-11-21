# 22 — APU: pulse channels and frame counter

**Depends on:** 12

## Goal

The APU skeleton: status/enable register, frame counter with its IRQ, the shared units (length counter, envelope,
sweep) and both pulse channels producing their 4-bit output per tick. No audio device yet.

## Context

- Registers: `$4000-$4003` pulse 1, `$4004-$4007` pulse 2, `$4015` enable/status, `$4017` frame counter.
- Frame counter: 4-step or 5-step sequence clocking envelopes/linear counter (quarter frame) and length
  counters/sweeps (half frame) at fixed CPU cycle positions; 4-step mode raises the frame IRQ unless inhibited.
  Writing `$4017` takes effect after 3 or 4 CPU cycles; 5-step mode clocks immediately on write.
- Reading `$4015` returns length-counter status, frame IRQ and DMC IRQ flags, and clears the frame IRQ flag.
- Pulse: 11-bit timer (clocked every other CPU cycle), 8-step duty sequencer (4 duties), envelope (constant or
  decaying volume), sweep (pulse 1 negates with one's complement, pulse 2 with two's complement; mutes when the target
  period overflows or the period is < 8), length counter from a 32-entry table.

## Scope

In: everything above; the APU ticked by the console once per CPU cycle; frame IRQ wired to the CPU IRQ line.

Out: triangle, noise, DMC, mixer (plan 23); audio output (plan 24).

## Open decisions

- `$4015` and open bus: the APU page says "the external CPU data bus is disconnected when reading" `$4015`, so "the
  value does not affect open bus". Plan 04's device contract (`cpu_read(address, data_bus)` → the byte left on the
  bus, stored by `CpuBus`) cannot hand the CPU one value and leave another on the bus. Options: a CPU-internal read
  path in `CpuBus` for `$4015`, or a second return channel. Decide here, with a spec citing the APU page.
- Sharing `$4000-$4017`: settled by plan 15 (decision 1). `CpuBus` splits the range: the APU goes in the
  `apu_registers:` slot (`$4000-$4015` and writes to `$4017`); reads of `$4016`/`$4017` and writes to `$4016` go to
  the `controller_ports:` slot, and writes to `$4014` to `CpuBus::OamDma`.
- Tick granularity: per CPU cycle (simple, many calls) vs catch-up on register access and at frame end (faster,
  more complex). Recommendation: per cycle now; plan 25 decides if catch-up pays off.

- IRQ line: plan 21 (decision 5) implemented the wired-OR push of plan 12 (decision 3): each source asserts and
  releases its own bit with `Cpu#assert_irq(source)` / `Cpu#release_irq(source)` (`Cpu::InterruptLines`, the mapper's
  bit first); the frame counter here and the DMC in plan 23 add theirs. Its level should reach the CPU's polling point
  the way plan 12's NMI edge does (decision 2); it is still polled before each instruction without a cycle.
- CPU interrupt gaps that become testable with the frame IRQ (`docs/architecture.md`, Known gaps): the `CLI`/`SEI`/`PLP`
  delay, interrupt hijacking and the branch polling quirk, checked by `cpu_interrupts_v2` 1, 3, 4 and 5 (plan 12
  recorded their failures). Model each or record why it stays a gap.

## Tasks

- [ ] Specify and test the length counter (table load, halt, disable via `$4015`), envelope, sweep (both negate modes,
      muting), duty sequencer, timer.
- [ ] Specify and test the frame counter (both modes, write delay, IRQ inhibit, IRQ flag cleared by `$4015` read).
- [ ] Add `apu_test` (and `instr_timing`, which uses the APU length counter as a timer) to the manifest, plus
      `instr_misc/04-dummy_reads_apu`; rerun the `cpu_interrupts_v2` singles already in it.

## Acceptance criteria

- [ ] `apu_test` `1-len_ctr`, `2-len_table` and `3-irq_flag` pass; `4-jitter`, `5-len_timing`, `6-irq_flag_timing`
      results recorded with reasons.
- [ ] `cpu_interrupts_v2` `1-cli_latency` and `instr_misc/04-dummy_reads_apu` pass, or their failures are recorded
      with the reason; the Known gaps rows they cover are updated.
- [ ] `instr_timing` result recorded (pass expected if the clock model holds; otherwise reason documented).
- [ ] 100% branch coverage on APU code so far; rubocop clean.

## References

- APU — https://www.nesdev.org/wiki/APU
- APU Frame Counter — https://www.nesdev.org/wiki/APU_Frame_Counter
- APU Length Counter — https://www.nesdev.org/wiki/APU_Length_Counter
- APU Envelope — https://www.nesdev.org/wiki/APU_Envelope
- APU Sweep — https://www.nesdev.org/wiki/APU_Sweep
- APU Pulse — https://www.nesdev.org/wiki/APU_Pulse
- `apu_test` — https://github.com/christopherpow/nes-test-roms (`apu_test/readme.txt`)
