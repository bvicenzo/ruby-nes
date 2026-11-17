# 05 — CPU registers and addressing modes

**Depends on:** 04

## Goal

The 6502 register file, the status flags and all addressing modes, each returning the effective address (or operand)
and the extra cycles it costs — the foundation the instruction table (plan 06) is built on.

## Context

Registers: `A`, `X`, `Y` (8-bit), `SP` (8-bit, stack at `$0100-$01FF`, grows down), `PC` (16-bit), `P` status.

Status `P` bits (7→0): `N V - B D I Z C`. Bit 5 has no storage and reads as 1 when pushed; `B` exists only in the copy
pushed to the stack (1 for `PHP`/`BRK`, 0 for IRQ/NMI). `D` can be set/cleared but has no effect on the 2A03.

Addressing modes:

| Mode | Notes |
|---|---|
| Implied / Accumulator | no operand |
| Immediate `#$nn` | operand is the next byte |
| Zero page `$nn` | |
| Zero page,X / Zero page,Y | wraps within page zero (`($nn + X) & $FF`) |
| Relative | signed 8-bit offset for branches |
| Absolute `$nnnn` | |
| Absolute,X / Absolute,Y | +1 cycle on page cross **for read instructions only** |
| Indirect `($nnnn)` | `JMP` only; the high byte is fetched without carrying into the page (`$xxFF` bug) |
| Indexed indirect `($nn,X)` | pointer read wraps in page zero |
| Indirect indexed `($nn),Y` | pointer read wraps in page zero; +1 cycle on page cross for reads |

## Scope

In: `Cpu` state, flag helpers (set Z/N from a value, etc.), stack push/pull, each addressing mode resolver with its
page-cross signal.

Out: instructions (plan 06), interrupts (plan 07).

## Open decisions

- Representation of `P`: one integer with bit masks (recommended: matches push/pull and the trace log) vs one ivar
  per flag (cheaper to update, costlier to pack). Benchmark candidate for plan 10.

## Tasks

- [ ] Specify and test flag helpers and stack operations (wrap of `SP` at `$00`/`$FF`, bit 5/B on push).
- [ ] Specify and test every addressing mode, including each wrap and page-cross boundary
      (`$xxFE`/`$xxFF` → next page).
- [ ] Implement under `Ruby::Nes::Cpu`, following the hot-path rules from plan 01.

## Acceptance criteria

- [ ] Each addressing mode has leaves for: no page cross, page cross (where relevant), zero-page wrap (where relevant).
- [ ] `JMP ($10FF)` reads the high byte from `$1000`, not `$1100`.
- [ ] Stack push at `SP = $00` wraps to `$FF` and writes `$0100`.
- [ ] 100% branch coverage; rubocop clean.

## References

- CPU registers — https://www.nesdev.org/wiki/CPU_registers
- Status flags — https://www.nesdev.org/wiki/Status_flags
- CPU addressing modes — https://www.nesdev.org/wiki/CPU_addressing_modes
- Stack — https://www.nesdev.org/wiki/Stack
- Obelisk 6502 reference (addressing) — https://www.nesdev.org/obelisk-6502-guide/addressing.html
