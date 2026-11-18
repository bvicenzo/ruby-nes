# 06 — CPU official instructions

**Depends on:** 05

## Goal

All 56 official 6502 instructions (151 opcodes) with correct flags and cycle counts, executed by `Cpu#step`.

## Context

Instruction groups: loads/stores (`LDA LDX LDY STA STX STY`), transfers (`TAX TAY TXA TYA TSX TXS`), stack
(`PHA PHP PLA PLP`), logic (`AND EOR ORA BIT`), arithmetic (`ADC SBC CMP CPX CPY`), inc/dec (`INC INX INY DEC DEX
DEY`), shifts (`ASL LSR ROL ROR`, accumulator and memory), jumps/calls (`JMP JSR RTS RTI`), branches (`BCC BCS BEQ BMI
BNE BPL BVC BVS`), flags (`CLC CLD CLI CLV SEC SED SEI`), `BRK`, `NOP`.

Cycle rules: base cycles per opcode; +1 on page cross for read instructions in indexed modes; branches +1 when taken
and +1 more when the target is on another page; read-modify-write instructions never get the page-cross bonus (always
the full count). The 2A03 ignores decimal mode in `ADC`/`SBC`.

`ADC` overflow: `V = ~(A ^ operand) & (A ^ result) & $80`. `SBC` is `ADC` with the operand inverted.

From plan 05: every addressing mode is a `Cpu` method returning the effective address (`immediate_address`,
`absolute_x_address`, …). The page-cross cycle of indexed reads is charged by the `_for_read` resolvers
(`absolute_x_address_for_read`, `absolute_y_address_for_read`, `indirect_indexed_address_for_read`), which add 1 to
`Cpu#cycles`; the opcode table's page-cross rule is the choice of resolver, and write/read-modify-write opcodes use
the plain ones. `relative_address` returns the branch target only: the taken and page-cross cycles of branches are
this plan's. Flags go through `Cpu::Status` (`update_zero_and_negative`, `carry=`, …), the stack through `Cpu::Stack`
(`push_word` pushes the high byte first). Dummy reads are not modelled (plan 05, decision 3).

## Scope

In: an opcode table (opcode → mnemonic, mode, base cycles, page-cross rule), the dispatch in `Cpu#step`, every official
instruction. `BRK` pushes and jumps through `$FFFE` (full interrupt semantics in plan 07).

Out: unofficial opcodes (plan 09; until then an unknown opcode raises a named error with the PC), interrupts.

## Open decisions

- Dispatch strategy: one big `case opcode` vs an Array of method names/lambdas indexed by opcode vs generated
  methods. Recommendation: start with `case` (clearest, JIT-friendly), compare in plan 10.
- Spec granularity: one spec file per instruction group (recommended) vs one per instruction.

## Tasks

- [ ] For each group: prose description → `specify-behavior` → `write-tests` → implement.
- [ ] Opcode table with cycles from the reference; a spec cross-checks the table's opcode count (151 official).
- [ ] `ADC`/`SBC`: leaves for carry in/out and signed overflow in both directions.
- [ ] Branches: leaves for not taken, taken same page, taken crossing page (forward and backward).

## Acceptance criteria

- [ ] All 151 official opcodes execute; executing an unofficial one raises an error naming opcode and PC.
- [ ] Every instruction's flag effects are spec leaves (only the flags it touches change).
- [ ] Cycle counts match the reference for every opcode, including page-cross and branch penalties.
- [ ] 100% branch coverage on the CPU; rubocop clean.

## References

- Instruction reference — https://www.nesdev.org/wiki/Instruction_reference
- Obelisk 6502 reference — https://www.nesdev.org/obelisk-6502-guide/reference.html
- 6502 cycle-by-cycle behaviour — https://www.nesdev.org/6502_cpu.txt
- Overflow flag explained — http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html
