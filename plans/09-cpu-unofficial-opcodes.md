# 09 — CPU unofficial opcodes

**Depends on:** 08

## Goal

Implement the unofficial opcodes so the **entire** `nestest.log` matches, and decide what to do with the unstable
ones. Milestone M1.

## Context

The 105 opcodes outside the official set include:

- Stable and used by some games / tested by nestest: multi-byte `NOP`s (`DOP`/`TOP` with reads), `LAX`, `SAX`,
  `SBC $EB`, and the read-modify-write combos `DCP`, `ISB` (`ISC`), `SLO`, `RLA`, `SRE`, `RRA`.
- Immediate combos: `ANC`, `ALR` (`ASR`), `ARR`, `AXS` (`SBX`).
- Unstable (depend on chip/analog effects): `XAA`/`ANE`, `LAX #imm`, `SHA`/`AHX`, `SHX`, `SHY`, `TAS`, `LAS`.
- `JAM`/`KIL` opcodes that halt the CPU.

## Scope

In: every opcode nestest uses; the immediate combos; `JAM` halting the CPU (with a named state, not an exception
loop).

Out (decision): the unstable group.

## Open decisions

- Unstable opcodes: implement with the commonly documented "magic constant" behaviour, or raise as unsupported?
  Recommendation: implement the documented behaviour, flagged as approximate in comments; no commercial US game
  depends on them.
- `JAM`: halt silently (real hardware) or raise in development? Recommendation: halt and expose `cpu.jammed?`, so
  the frontend can show it.

## Tasks

- [ ] Specify and test each unofficial opcode (they share the addressing modes from plan 05; reuse those leaves'
      structure, not their code).
- [ ] Extend the nestest integration spec to the full log.
- [ ] Opcode table spec: all 256 opcodes are defined.

## Acceptance criteria

- [ ] The full `nestest.log` matches in PC, bytes, A, X, Y, P, SP and CYC.
- [ ] `$0002` and `$0003` are `$00` at the end of the run.
- [ ] All 256 opcodes have a table entry; none raises "unknown opcode".
- [ ] `JAM` behaviour is specified and implemented as decided.
- [ ] 100% branch coverage on the CPU; rubocop clean.

Note: blargg's `instr_test-v5` suite waits on the PPU's VBlank flag before running, so it becomes an acceptance
criterion of plan 12, not of this plan.

## References

- CPU unofficial opcodes — https://www.nesdev.org/wiki/CPU_unofficial_opcodes
- Programming with unofficial opcodes — https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes
- "No More Secrets" (detailed unofficial opcode document) — https://csdb.dk/release/?id=198357
