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

- Tick granularity: per CPU cycle (simple, many calls) vs catch-up on register access and at frame end (faster,
  more complex). Recommendation: per cycle now; plan 25 decides if catch-up pays off.

## Tasks

- [ ] Specify and test the length counter (table load, halt, disable via `$4015`), envelope, sweep (both negate modes,
      muting), duty sequencer, timer.
- [ ] Specify and test the frame counter (both modes, write delay, IRQ inhibit, IRQ flag cleared by `$4015` read).
- [ ] Add `apu_test` (and `instr_timing`, which uses the APU length counter as a timer) to the manifest.

## Acceptance criteria

- [ ] `apu_test` `1-len_ctr`, `2-len_table` and `3-irq_flag` pass; `4-jitter`, `5-len_timing`, `6-irq_flag_timing`
      results recorded with reasons.
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
