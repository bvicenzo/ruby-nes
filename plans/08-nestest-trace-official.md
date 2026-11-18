# 08 — nestest trace (official opcodes)

**Depends on:** 02, 07

## Goal

Run `nestest.nes` in automation mode and match the reference `nestest.log` line by line for the whole official-opcode
section. First objective proof the CPU is right.

## Context

`nestest` has an automation mode: set `PC = $C000` instead of the reset vector and it runs all tests without a PPU.
The reference log (from Nintendulator) starts:

```text
C000  4C F5 C5  JMP $C5F5                       A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7
```

Initial state for automation mode: `P = $24`, `SP = $FD`, cycle counter 7. Lines whose disassembly starts with `*`
are unofficial opcodes; the official section is everything before the first of them. Test results are written to
`$0002` and `$0003` (zero means pass; non-zero codes are listed in the ROM's documentation).

## Scope

In:

- `Debug::Tracer` (`lib/ruby/nes/debug/tracer.rb`, off the hot path per `docs/architecture.md`): formats the state
  *before* each instruction in nestest's format (PC, raw bytes, A, X, Y, P, SP, CYC; disassembly and PPU columns
  optional — see decision).
- A context, in the spec tree of the entry point that produces the trace (never a `describe` of its own), declaring
  `test_rom: ['other/nestest.nes', 'other/nestest.log']` (plan 02) and comparing our trace to the log until the first
  `*` line, failing on the first divergence with both lines and the line number.
- A rake task `nestest:diff` that prints the first divergence (debugging aid).

Out: unofficial opcodes (plan 09).

## Open decisions

- Compare the disassembly text and the `PPU:` column, or only machine state (PC, bytes, registers, CYC)?
  Recommendation: machine state only now; the PPU column becomes meaningful after plan 12.

## Tasks

- [ ] Specify and test the tracer's formatting on synthetic states (no ROM).
- [ ] Integration spec over the log; diff task.
- [ ] Fix CPU bugs found (each fix gets a unit spec leaf first — never fix only to the log).

## Acceptance criteria

- [ ] Every line before the first unofficial opcode matches in PC, bytes, A, X, Y, P, SP and CYC.
- [ ] `$0002` is `$00` when execution reaches the unofficial section.
- [ ] Each CPU bug found by the log has a unit spec reproducing it.
- [ ] Spec runs in under a few seconds without a JIT (record the time; it is the first benchmark data point).

## References

- Emulator tests (nestest entry) — https://www.nesdev.org/wiki/Emulator_tests
- nestest documentation — `other/nestest.txt` in https://github.com/christopherpow/nes-test-roms
- Trace log format discussion — https://www.nesdev.org/wiki/Emulator_tests#CPU
