# 08 — nestest trace (official opcodes)

**Status:** done (2026-11-18)

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

Initial state for automation mode: `P = $24`, `SP = $FD`, cycle counter 7 — exactly a powered-up CPU (`Cpu.new`
followed by `Cpu#reset`, plan 07), after which the program counter is set to `$C000`. Lines whose disassembly
starts with `*` are unofficial opcodes; the official section is everything before the first of them. Test results
are written to `$0002` and `$0003` (zero means pass; non-zero codes are listed in the ROM's documentation).

`P` in the log is the interrupt-pushed form of `Cpu::Status` (bit 5 set, B clear: `P:24`); the
[Status flags](https://www.nesdev.org/wiki/Status_flags) page says debuggers have "no convention" for bits 5 and 4,
so the tracer follows nestest.

A diagnostic run before this plan started (2026-11-18, not committed) already matched PC, A, X, Y, P, SP and CYC on
all 5003 official lines; the first unofficial line is 5004 (`C6BD *NOP`), where `$0002` and `$0003` are `$00`. Every
mnemonic of `Cpu::Opcodes` matched the log, and each of the 13 addressing modes appeared with a single instruction
length. The work of this plan is therefore mostly the tooling that keeps that proof in the suite.

## Scope

In:

- `Cpu::Opcodes::Opcode#size`: the instruction's length in bytes, one opcode byte plus the operand bytes of its
  addressing mode (`Opcodes::OPERAND_SIZES`).
- `Debug::Tracer` (`lib/ruby/nes/debug/tracer.rb`, off the hot path per `docs/architecture.md`): `Tracer.new(cpu:,
  bus:)`, `#line` formats the state *before* the next instruction (decision 5). The instruction length and mnemonic
  come from `Cpu::Opcodes` (plan 06). That table's `mode:` is a second copy of the addressing mode the dispatch
  (`Cpu::Dispatch`) resolves, and no plan 06 spec ties the two together: the trace comparison is what validates it (a
  wrong mode shows up as a wrong instruction length), and the same holds for the mnemonic (decision 1).
- Test tooling in `spec/support/nestest/` (decision 4):
  - `Nestest::Log` — reads the log and reduces each line before the first `*` to the tracer's layout (drops the
    operand text and the `PPU:` column).
  - `Nestest::Runner` — `Runner.automation_mode(cartridge)` builds the mapper, bus and a powered-up CPU with
    `PC = $C000` (decision 6); `#first_divergence(expected_lines)` steps and compares, returning `nil` or a
    `Nestest::Divergence` (line number, expected, actual, message); `#official_result` is the byte at `$0002`.
  - Contexts in the spec trees of `#first_divergence` and `#official_result` (never a `describe` of their own),
    declaring `test_rom: ['other/nestest.nes', 'other/nestest.log']` (plan 02): no divergence until the first `*`
    line, and `$0002` is `$00` there.
- A rake task `nestest:diff` that prints the first divergence or the success (debugging aid).

Out: unofficial opcodes (plan 09); the operand text and the `PPU:` column (decision 1).

## Decisions

Settled with the user on 2026-11-18.

1. **Compared columns: PC, bytes, mnemonic, A, X, Y, P, SP and CYC.** Not the operand text, not `PPU:`. Reason: the
   mnemonic validates `Opcodes`' mnemonic column, which no spec ties to the dispatch (the same argument as the mode);
   the operand text (`STX $00 = 00`) needs memory reads with side effects; `PPU:` is meaningful only after plan 12,
   which extends the comparison.
2. **The tracer reads the instruction bytes with `bus.read`; no `peek`.** It reads only the bytes the CPU fetches
   right after, so the data bus (open bus) ends the same once the step runs. A side-effect-free `peek` waits for a
   debugger that shows memory values.
3. **An opcode outside `Cpu::Opcodes` is traced as its single byte with the mnemonic `???`.** Reason: if the CPU
   wanders into garbage, the comparison reports the divergence with its line number instead of raising. Plan 09
   defines all 256 opcodes and removes this branch.
4. **The nestest tooling lives in `spec/support/nestest/`**, like `TestRoms`: it is tied to the test ROM fixture, it
   is measured by branch coverage, and `rakelib/` (and plan 10's bench) can require it. Only `Debug::Tracer` is in
   `lib/`.
5. **Tracer line layout:** `C000  4C F5 C5  JMP  A:00 X:00 Y:00 P:24 SP:FD CYC:7` — nestest's columns up to the
   mnemonic, then the machine state only. `Nestest::Log` reduces the log's lines to the same layout.
6. **`Nestest::Runner.automation_mode` takes a `Cartridge`, not a path** (settled during implementation): loading
   the file stays with the caller (`Cartridge::Loader.from_file`), and the synthetic spec builds an NROM cartridge in
   memory with `Cartridges.build`.

Review follow-ups (independent code review, accepted by the user):

- The real-ROM examples could pass vacuously (an empty official section compares nothing, and `$0002` starts at
  zero): `Nestest::Log` now has a nestest.log context (5003 lines, the last `C6BC PLP`) and `#first_divergence`'s
  nestest context checks the CPU stops at `$C6BD`.
- The tracer read the opcode byte twice; it now reads each instruction byte once (decision 2), with a leaf for it.
- An unknown opcode is a null `UNKNOWN_OPCODE` entry instead of two nil checks; the redundant P leaf of the tracer
  spec was removed; the `Opcode#size` table leaf checks that every official mode has an operand size.
- `rake nestest:diff` loads the emulator only when it runs; `TestRoms.requirement` is shared with `spec_helper`.
- Plan 12 gained a task: the tracer does not show a pending interrupt, which `Cpu#step` takes instead of the opcode.
- Not applied: raising on a malformed log line (the manifest's checksum guards the file, and the 5003-line context
  catches a broken parser); hoisting the repeated spec setup (it would redefine a parent's `subject`/`let` or bundle
  contexts by similarity); flattening the four-level nestest context (`CLAUDE.md`: trees shrink only through code);
  a synthetic leaf for the cartridge-to-bus wiring of `automation_mode` (the nestest contexts prove it).

## What was done

- `Cpu::Opcodes::Opcode#size` from `Opcodes::OPERAND_SIZES` (one entry per addressing mode); `Bits.wrap_to_word`.
- `Debug::Tracer#line`: nestest's columns up to the mnemonic, then A, X, Y, P (interrupt-pushed form), SP and CYC.
- `spec/support/nestest/`: `Nestest::Log` (the official section in the tracer's layout), `Nestest::Runner`
  (automation mode, `first_divergence`, `official_result`) and `Nestest::Divergence`; `rake nestest:diff`.
- nestest.log matches on all 5003 official lines and `$0002` is `$00`; no CPU bug was found. One full run takes
  about 0.07 s without a JIT.
- `docs/architecture.md`: layout row for the nestest tooling. Plans 09, 10 and 12 aligned. 862 examples, 100% line
  and branch coverage. One independent code review; its follow-ups are listed above.

## Tasks

- [x] Specify and test `Opcode#size` (one row per addressing mode).
- [x] Specify and test the tracer's formatting on synthetic states (no ROM). It needed `Bits.wrap_to_word` (the
      operand bytes wrap past `$FFFF` like the CPU's fetch), specified with it.
- [x] Specify and test `Nestest::Log` and `Nestest::Runner`, with the nestest contexts; the diff task.
- [x] Fix CPU bugs found (each fix gets a unit spec leaf first — never fix only to the log). None was found.
- [x] `docs/architecture.md`: layout row for `spec/support/nestest`; plans 09, 10 and 12 aligned.

## Acceptance criteria

- [x] Every line before the first unofficial opcode matches in PC, bytes, mnemonic, A, X, Y, P, SP and CYC
      (all 5003 lines; `rake nestest:diff` prints "All 5003 official lines match; $0002 = $00").
- [x] `$0002` is `$00` when execution reaches the unofficial section.
- [x] Each CPU bug found by the log has a unit spec reproducing it: the log found none (the CPU of plans 05-07
      matched from the first run).
- [x] Spec runs in under a few seconds without a JIT: one full run of the official section (5003 instructions,
      traced and compared) takes about 0.07 s under the interpreter (Ruby 4.0.9, x86_64-darwin24, 2026-11-18;
      `rspec --profile`), the first benchmark data point.
- [x] `rake nestest:diff` prints the first divergence or the success.
- [x] 100% branch coverage of the new units; rubocop clean; `bundle exec rake` green (862 examples).

## References

- Emulator tests (nestest entry) — https://www.nesdev.org/wiki/Emulator_tests
- nestest documentation — `other/nestest.txt` in https://github.com/christopherpow/nes-test-roms
- Trace log format discussion — https://www.nesdev.org/wiki/Emulator_tests#CPU
- CPU addressing modes (operand sizes) — https://www.nesdev.org/wiki/CPU_addressing_modes
- Status flags (bits 5 and 4 in debuggers) — https://www.nesdev.org/wiki/Status_flags
- CPU power up state (the automation mode's initial state) — https://www.nesdev.org/wiki/CPU_power_up_state
