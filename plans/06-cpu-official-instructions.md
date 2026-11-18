# 06 — CPU official instructions

**Status:** done (2026-11-18)

**Depends on:** 05

## Goal

All 56 official 6502 instructions (151 opcodes) with correct flags and cycle counts, executed by `Cpu#step`.

## Context

Instruction groups: loads/stores (`LDA LDX LDY STA STX STY`), transfers (`TAX TAY TXA TYA TSX TXS`), stack
(`PHA PHP PLA PLP`), logic (`AND EOR ORA BIT`), arithmetic (`ADC SBC`), comparisons (`CMP CPX CPY`), inc/dec (`INC
INX INY DEC DEX DEY`), shifts (`ASL LSR ROL ROR`, accumulator and memory), branches (`BCC BCS BEQ BMI BNE BPL BVC
BVS`), flags (`CLC CLD CLI CLV SEC SED SEI`), control flow (`JMP JSR RTS RTI BRK NOP`).

Cycle rules ([Instruction reference](https://www.nesdev.org/wiki/Instruction_reference)): base cycles per opcode;
indexed reads "(5 if page crossed)" / "(6 if page crossed)"; branches "2 (3 if branch taken, 4 if page crossed)", the
offset "relative to the first byte _after_ the branch instruction"; stores and read-modify-write instructions list no
page-cross penalty (their indexed cycle is in the base count).

Facts the specs rest on, all from the Instruction reference unless noted:

- **ADC**: C when the result "overflowed past $FF"; V = `(result ^ A) & (result ^ memory) & $80` ("If the result's
  sign is different from both A's and memory's"). **SBC**: V = `(result ^ A) & (result ^ ~memory) & $80`; "SBC
  subtracts 1 more when carry is _clear_" — it is ADC with the operand inverted. Decimal mode: "this mode is
  permanently disabled on the NES' 2A03 CPU. However, the flag itself still functions" (CLD/SED sections).
- **CMP/CPX/CPY**: C = register >= memory, Z = register == memory, N = bit 7 of the difference; "comparison does
  _not_ affect overflow".
- **BIT**: "Bits 7 and 6 of the memory value are loaded directly into the negative and overflow flags"; Z from "the
  accumulator AND memory value".
- **INC/DEC** do "_not_ affect carry nor overflow"; there is no accumulator form. **LSR** clears N.
- **ASL/LSR/ROL/ROR**: C takes the bit shifted out (bit 7 left, bit 0 right); ROL/ROR shift the old C in.
- **Transfers**: TAX TAY TXA TYA TSX set Z/N. TXS has no flag table on the Instruction reference; the
  [Obelisk reference](https://www.nesdev.org/obelisk-6502-guide/reference.html) marks every flag "Not affected".
- **PHP**: "The B flag and extra bit are both pushed as 1" (`Status#byte_pushed_by_instruction`). **PLP**: "The B
  flag and extra bit are ignored" (`Status#restore`). **PLA** sets Z/N.
- **JSR** pushes PC + 2: "the return address on the stack points 1 byte before the start of the next instruction".
  **RTS** pulls the address "and then increments the program counter". **RTI** pulls P then PC: "the return address
  is the exact address of the next instruction".
- **BRK** pushes PC + 2 ("the return address that is pushed to the stack skips the byte after the BRK opcode"), then
  P with B set, then sets I ("set to 1 after the old flags are pushed"), and jumps through `$FFFE`. Interrupt
  hijacking and the rest of plan 07 are out.
- The `CLI`/`SEI`/`PLP` delay on IRQ polling ("delayed one instruction because the flag is changed after IRQ is
  polled") is plan 07's: here the flag changes immediately.

From plan 05: every addressing mode is a `Cpu` method returning the effective address (`immediate_address`,
`absolute_x_address`, …). The page-cross cycle of indexed reads is charged by the `_for_read` resolvers, so the
dispatch's choice of resolver is the opcode's page-cross rule. `relative_address` returns the branch target only: the
taken and page-cross cycles of branches are this plan's. Flags go through `Cpu::Status`, the stack through
`Cpu::Stack`. Dummy reads are not modelled (plan 05, decision 3), and neither is the read-modify-write double write
(decision 5).

## Scope

In: the dispatch in `Cpu#step`, every official instruction, an opcode table (`Cpu::Opcodes`: mnemonic, addressing
mode, base cycles) used by `step` for the cycles and by the tracer (plan 08). `BRK` pushes and jumps through `$FFFE`
(full interrupt semantics in plan 07).

Out: unofficial opcodes (plan 09; until then an unknown opcode raises `Cpu::UnknownOpcode` naming opcode and PC),
interrupts, IRQ polling delays.

## Decisions

Settled with the user on 2026-11-18.

1. **Dispatch is one `case opcode`** in `Cpu#execute`, one `when 0xA9 then load_accumulator(immediate_address)` per
   opcode. Reason: Ruby compiles a `case` whose `when`s are integer literals into `opt_case_dispatch` (a hash lookup,
   O(1)), with no `Proc#call` or `send` per instruction — the shape YJIT/ZJIT compile best and Spinel can type. The
   method is the only one exempt from the size and complexity Metrics cops, with a comment stating this reason; logged
   in `docs/architecture.md`. Plan 10 compares it with a table of lambdas.
2. **Instruction methods are spelled out** (`load_accumulator`, `add_with_carry`, `branch_if_carry_clear`,
   `shift_left_accumulator` / `shift_left_memory`). Reason: the readability rule against abbreviations; the
   mnemonic (`'LDA'`) is data in `Cpu::Opcodes` (for the tracer) and appears in comments.
3. **`Cpu#step` specs are black-box rows**, one flat row per opcode (plus page-cross and branch variants): a program
   at `$8000`, an initial state, one observable effect and the reference cycle count. Reason: proves each opcode
   reaches the right instruction with the right mode without mocking the subject; flag details stay in the group
   specs. A long flat tree of data is not a design smell (CLAUDE.md).
4. **One mixin per group** in `lib/ruby/nes/cpu/instructions/` (`LoadStore`, `Transfers`, `StackOperations`,
   `Logic`, `Arithmetic`, `Comparisons`, `IncrementDecrement`, `Shifts`, `Branches`, `Flags`, `ControlFlow`),
   included in `Cpu` like `AddressingModes`, each with its spec in `spec/ruby/nes/cpu/instructions/`. Reason: small
   modules and small spec trees; instructions receive the resolved effective address (or nothing, for implied and
   accumulator modes).
5. **The read-modify-write double write is not modelled**: those instructions "first [write] the original value back
   to memory" (Instruction reference). Listed in Known gaps; plan 20 revisits it, since the MMC1 serial port "ignores
   every write after the first" on consecutive cycles, which "only happens when the CPU executes read-modify-write
   instructions" ([MMC1](https://www.nesdev.org/wiki/MMC1)).

Settled during the implementation:

6. **Shifts go through a `Cpu::Shifter`** (`shift_left`, `shift_right`, `rotate_left`, `rotate_right`: return the
   byte, set C, Z and N), built once by `Cpu`. The eight `Shifts` methods only say where the byte comes from and goes.
   Reason: four operations times two targets made the spec tree a cross-product of the same leaves (~56); now the
   operations are specified once and each instruction by one leaf. One extra call, no allocation.
7. **`Branches#take_branch(target)` is public** and holds the branch mechanics (the taken cycle and the page-cross
   cycle); each of the eight branches is specified only by its condition. Reason: the same cross-product, without a
   new object.
8. **`Cpu.new` takes `stack_pointer:`** like the other registers (default 0 until plan 07). Reason: specs declare the
   stack pointer instead of mutating `cpu.stack.pointer`. `Metrics/ParameterLists` is disabled on that one method:
   one optional keyword per register (Decisions log, row 12).
9. **Names:** the error is `Cpu::UnknownOpcode` (the project's error classes carry no `Error` suffix, as
   `Mappers::UnsupportedMapper`); BRK is `force_interrupt` (the Obelisk name; `break` is a Ruby keyword). The `#step`
   rows live in `spec/ruby/nes/cpu_step_spec.rb` (the path RuboCop expects for `Cpu`'s `describe '#step'`).

## What was done

- One `Cpu` mixin per instruction group in `lib/ruby/nes/cpu/instructions/` (`LoadStore`, `Transfers`,
  `StackOperations`, `Logic`, `Arithmetic`, `Comparisons`, `IncrementDecrement`, `Shifts`, `Branches`, `Flags`,
  `ControlFlow`), every instruction a spelled-out method taking the resolved effective address.
- `Cpu::Shifter` for ASL/LSR/ROL/ROR; `Branches#take_branch` for the taken and page-cross cycles (decisions 6, 7).
- `Cpu::Dispatch#execute`: one `case` with 151 integer `when`s (verified to compile into `opt_case_dispatch`), the
  only method exempt from the size and complexity Metrics cops. `Cpu::Opcodes::TABLE`: mnemonic, mode and base cycles
  for the plan 08 tracer. `Cpu#step` returns the cycles each instruction took; an unofficial opcode raises
  `Cpu::UnknownOpcode` with the opcode and its address.
- `Cpu.new` takes `stack_pointer:`; a private `Cpu#read_word` reads vectors (BRK now, NMI and reset in plan 07).
- Spec support: `FlatBus#write_bytes` loads a program in one call. `spec/ruby/nes/cpu_step_spec.rb` has one black-box
  row per opcode plus page-cross rows for every indexed opcode and a taken/not-taken pair per branch.
- `docs/architecture.md`: layout rows, the read-modify-write double write in Known gaps, decisions 9-12.
  `docs/GLOSSARY.md`: `bitwise-and`, `bitwise-or`, `bitwise-exclusive-or`, `invert-byte`, `signed-overflow`. Plans 08,
  10 and 20 aligned.
- 437 new examples (772 in all), 100% line and branch coverage. A diagnostic run of `nestest.nes` from `$C000` (not
  committed; plan 08 formalises it) matched all 5003 official lines of `nestest.log` in PC, A, X, Y, P, SP and CYC,
  with `$0002 = $00`, in about 0.4 s without a JIT.
- One independent code review, no correctness bug. Applied: the Metrics exemption wording and a Decisions log row for
  `stack_pointer:`, the branch cycle comment, a note in plan 08 that the trace validates the table's `mode:`,
  `read_word` moved to `Cpu` with a word wrap, three references added, naming and tag nits. Not applied: shared
  examples for the Z/N leaves (no shared production code behind them) and a `BASE_CYCLES` array (left to plan 10).

## Tasks

- [x] For each group: prose description → `specify-behavior` → `write-tests` → implement.
- [x] `ADC`/`SBC`: leaves for carry in/out and signed overflow in both directions; decimal flag ignored.
- [x] Branches: leaves for not taken, taken same page, taken crossing page (forward and backward).
- [x] `Cpu::Opcodes` table with cycles from the reference; a spec checks it holds the 151 official opcodes.
- [x] `Cpu#step`: one black-box row per opcode with its cycles; page-cross rows for indexed reads; unknown opcode error.
- [x] `docs/architecture.md`: layout row for `cpu/instructions/`, Decisions log (dispatch), Known gaps (RMW double
      write). `docs/GLOSSARY.md`: any new bit idiom.

## Acceptance criteria

- [x] All 151 official opcodes execute; executing an unofficial one raises an error naming opcode and PC.
- [x] Every instruction's flag effects are spec leaves (only the flags it touches change).
- [x] Cycle counts match the reference for every opcode, including page-cross and branch penalties.
- [x] The `case` dispatch carries its justified `rubocop:disable`; the decision is in the Decisions log; the RMW double
      write is in Known gaps.
- [x] 100% branch coverage on the CPU; rubocop clean; `bundle exec rake` green.

## References

- Instruction reference — https://www.nesdev.org/wiki/Instruction_reference
- Obelisk 6502 reference (TXS flags) — https://www.nesdev.org/obelisk-6502-guide/reference.html
- 6502 cycle-by-cycle behaviour — https://www.nesdev.org/6502_cpu.txt
- Overflow flag explained — http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html
- MMC1 (consecutive-cycle writes) — https://www.nesdev.org/wiki/MMC1
- CPU interrupts (the IRQ/BRK vector at `$FFFE`) — https://www.nesdev.org/wiki/CPU_interrupts
- Stack (descending, empty, words high byte first) — https://www.nesdev.org/wiki/Stack
- CPU unofficial opcodes (the 105 opcodes left to plan 09) — https://www.nesdev.org/wiki/CPU_unofficial_opcodes
- Ruby `case` dispatch: `RubyVM::InstructionSequence.of(Cpu::Dispatch.instance_method(:execute)).disasm` shows
  `opt_case_dispatch` on Ruby 4.0.9 (checked 2026-11-18); plan 10 measures it
