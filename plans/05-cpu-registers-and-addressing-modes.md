# 05 — CPU registers and addressing modes

**Status:** in progress (base af6058a)

**Depends on:** 04

## Goal

The 6502 register file, the status flags, the stack and all addressing modes, each returning the effective address
and charging the extra cycle it costs — the foundation the instruction table (plan 06) is built on.

## Context

Registers ([CPU registers](https://www.nesdev.org/wiki/CPU_registers)): "A is byte-wide", "X and Y are byte-wide",
"The 2-byte program counter PC supports 65536 direct (unbanked) memory locations", "S is byte-wide", "P has 6 bits
used by the ALU but is byte-wide".

Status `P` ([Status flags](https://www.nesdev.org/wiki/Status_flags)), bits 7→0 `NV1B DIZC`: bit 5 has "No CPU
effect; always pushed as 1"; "B is 0 when pushed by interrupts (NMI and IRQ) and 1 when pushed by instructions (BRK
and PHP)"; "The two bits with no CPU effect are ignored when pulling flags from the stack". `D`: "On the NES, decimal
mode is disabled and so this flag has no effect. However, it still exists and can be observed and modified". For
debuggers "there is no convention for what values to use for bits 5 and 4".

Stack ([Stack](https://www.nesdev.org/wiki/Stack)): page `$0100-$01FF`, descending and empty ("if S = $FD, and the
program pushes something, it'll be written to $01FD and then S becomes $FC"); `S` wraps "after reaching $00". The
wrap from `$FF` to `$00` on a pull is not stated; it follows from `S` being byte-wide and "whenever anything is being
pushed on the stack, it will be stored to the address $0100+S" ([6502_cpu.txt](https://www.nesdev.org/6502_cpu.txt)).
16-bit values are pushed high byte first (JSR in the
[Instruction reference](https://www.nesdev.org/wiki/Instruction_reference)).

Addressing modes ([CPU addressing modes](https://www.nesdev.org/wiki/CPU_addressing_modes)):

| Mode | Notes |
|---|---|
| Implied / Accumulator | no operand: nothing to resolve, plan 06 acts on the register |
| Immediate `#$nn` | the operand is the next byte; its address is `PC` |
| Zero page `$nn` | |
| Zero page,X / Zero page,Y | `PEEK((arg + X) % 256)`: wraps within page zero |
| Relative | "an 8-bit signed offset", "relative to the first byte after the branch instruction" (Instruction reference) |
| Absolute `$nnnn` | |
| Absolute,X / Absolute,Y | "+ means add a cycle for write instructions or for page wrapping on read instructions" |
| Indirect `($nnnn)` | `JMP` only: "JMP ($03FF) reads $03FF and $0300 instead of $0400" (Instruction reference) |
| Indexed indirect `($nn,X)` | pointer bytes at `(arg + X) % 256` and `(arg + X + 1) % 256` |
| Indirect indexed `($nn),Y` | pointer bytes at `arg` and `(arg + 1) % 256`; "+" cycle like absolute indexed |

Write instructions always pay the indexed cycle (it is in plan 06's base count); read instructions pay it only when
the page is crossed. No page documents the effective address of absolute indexed or `($nn),Y` going past `$FFFF`; it
wraps to `$0000` because the address is 16 bits wide (decision 6).

On a page cross the 6502 "reads an incorrect location first, a location that is smaller by one page", and indexed
writes always read before writing (6502_cpu.txt). Those dummy reads are not modelled here (decision 3).

## Scope

In: `Cpu` state and operand fetch, `Cpu::Status`, `Cpu::Stack`, one resolver per addressing mode with its page-cross
cycle, the bit constants in `Ruby::Nes::Bits`, the `FlatBus` spec double.

Out: instructions and branch cycles (plan 06), interrupts and power-up state (plan 07), dummy reads (decision 3).

## Decisions

Settled with the user on 2026-11-18.

1. **`P` is a `Cpu::Status` object holding one Integer with bit masks.** Named predicates and setters per flag,
   `update_zero_and_negative(value)`, the byte pushed by an instruction (B and bit 5 set) or by an interrupt (bit 5
   set, B clear), and `restore(byte)` dropping B (bit 5 is not stored: both pushed forms force it to 1). Reason: an Integer matches push/pull and the trace, and
   the object hides the representation, so plan 10's benchmark (Integer vs one ivar per flag) swaps only this class.
2. **The page-cross cycle is charged by a read variant of the resolver (tell, don't ask).** Absolute,X, absolute,Y
   and `($nn),Y` each have a plain resolver (write and read-modify-write instructions: never charges) and a
   `_for_read` one that adds 1 to `Cpu#cycles` when the page is crossed. Plan 06's opcode table picks the variant.
   Reason: no flag for the instruction to query, no second return value.
3. **Dummy reads are deferred** and listed as a known gap in `docs/architecture.md`. Reason: they only matter for
   registers with read side effects (`$2002`, `$2007`) and open bus, which need the PPU; revisit with the
   `cpu_dummy_reads` test ROM once the PPU exists (plan 12).
4. **The stack is a `Cpu::Stack` object** (`pointer`, `push`, `pull`, `push_word`, `pull_word`) on the CPU bus.
   Reason: one small cohesive unit; TSX/TXS and the tracer read `stack.pointer`.
5. **CPU specs use `FlatBus`** (`spec/support/flat_bus.rb`), 64 KiB with no decoding. Reason: specs about addressing
   must not depend on `CpuBus` mirrors (`$10FF`, `$1000` and `$1100` would all be RAM mirrors there).
6. **16-bit effective addresses wrap past `$FFFF`**, and the stack pointer wraps both ways. Reason: derived from the
   register widths on CPU registers, not from a documented quirk. A `_for_read` resolver wrapping from `$FFxx` to
   `$00xx` charges the page-cross cycle: the high byte changes, and 6502_cpu.txt has the CPU "fix the high byte of
   effective address" in an extra cycle whenever the index carries.
7. **The bit constants (`BYTE_MASK`, `WORD_MASK`, `PAGE_MASK`, `SIGN_BIT`, `BYTE_RANGE`) live in `Ruby::Nes::Bits`**
   and hot-path classes refer to them as `Bits::BYTE_MASK` (no aliases). Reason: the glossary already names them; one
   definition, and each file states where its constants come from.
8. **Registers start at zero** until plan 07 defines the power-up state.

## Tasks

- [x] Specify and test `Cpu::Status`: each flag, zero/negative update, both pushed bytes, restore dropping B.
- [x] Specify and test `Cpu::Stack`: push/pull, wrap of `SP` at `$00`/`$FF`, word order.
- [x] Specify and test `Cpu` state and `fetch_byte`/`fetch_word` (PC wrap at `$FFFF`).
- [x] Specify and test every addressing mode, including each wrap and page-cross boundary (`$xxFF` → next page).
- [x] Implement under `Ruby::Nes::Cpu`, following the hot-path rules of `docs/architecture.md`.
- [x] `docs/architecture.md`: layout rows, known gaps (dummy reads), decisions log. `docs/GLOSSARY.md`: new idioms.

## Acceptance criteria

- [x] Each resolver has leaves for: no page cross, page cross (where relevant), zero-page wrap (where relevant), and
      wrap past `$FFFF` (absolute indexed, `($nn),Y`, relative).
- [x] `_for_read` resolvers add one cycle only on a page cross; plain resolvers never add one.
- [x] `JMP ($10FF)` reads the high byte from `$1000`, not `$1100`.
- [x] Push at `SP = $00` writes `$0100` and leaves `SP = $FF`; pull at `SP = $FF` reads `$0100` and leaves `SP = $00`.
- [x] Pushed status: bit 5 always set, B set by instructions and clear by interrupts; `restore` drops B; bit 5 is not
      stored and both pushed forms force it to 1.
- [x] 100% branch coverage on `Cpu`, `Status`, `Stack` and the addressing modes; rubocop clean; `bundle exec rake`
      green.

## References

- CPU registers — https://www.nesdev.org/wiki/CPU_registers
- Status flags — https://www.nesdev.org/wiki/Status_flags
- CPU addressing modes — https://www.nesdev.org/wiki/CPU_addressing_modes
- Stack — https://www.nesdev.org/wiki/Stack
- Instruction reference (JMP indirect, branches, JSR) — https://www.nesdev.org/wiki/Instruction_reference
- 6502 cycle-by-cycle behaviour (dummy reads, page wrap) — https://www.nesdev.org/6502_cpu.txt
- Obelisk 6502 reference (addressing) — https://www.nesdev.org/obelisk-6502-guide/addressing.html
