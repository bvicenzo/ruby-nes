# 07 — CPU interrupts and power-up

**Depends on:** 06

## Goal

Reset, NMI, IRQ and BRK with correct vectors, stack contents, flag handling and cycle cost; and a documented power-up
state.

## Context

Vectors: NMI `$FFFA`, Reset `$FFFC`, IRQ/BRK `$FFFE` (little-endian). An interrupt sequence costs 7 cycles: push PC
high, PC low, P (B clear for NMI/IRQ, set for BRK; bit 5 set), set `I`, load PC from the vector.

- NMI is edge-triggered (the PPU raises it at VBlank); it cannot be masked by `I`.
- IRQ is level-triggered (mapper, APU frame counter, DMC); ignored while `I` is set.
- `RTI` restores P (ignoring B and bit 5) and PC; `CLI`/`SEI`/`PLP` change `I` with a one-instruction delay on IRQ
  polling (documented quirk; decide below whether to model it now).
- Reset: does not write the stack but decrements `SP` by 3; sets `I`; PC from `$FFFC`.
- Power-up: `A=X=Y=0`, `P=$34` (I set), `SP=$FD` after the reset sequence.

From plan 05: registers start at zero until this plan sets the power-up state; interrupts push PC with
`Cpu::Stack#push_word` and P with `Cpu::Status`'s interrupt-pushed byte (B clear, bit 5 set); `RTI` uses
`Status#restore`, which already ignores bits 4 and 5.

## Scope

In: `Cpu#reset`, `Cpu#nmi!` (edge latch), `Cpu#irq_line` (level), polling between instructions, `BRK`/`RTI` finished.

Out: who raises NMI/IRQ (PPU plan 12, mappers plan 21, APU plan 22).

## Open decisions

- Interrupt hijacking and the `CLI`/`SEI`/`PLP` polling delay: model now or defer until a test ROM requires it
  (`cpu_interrupts_v2`)? Recommendation: defer, record as a known gap.

## Tasks

- [ ] Specify and test reset (power-up vs soft reset), NMI, IRQ (masked and unmasked), BRK, RTI.
- [ ] Leaves for: NMI while `I` set (still taken), IRQ while `I` set (not taken), IRQ line still asserted after RTI
      (taken again), pending NMI and IRQ at the same time (NMI wins).

## Acceptance criteria

- [ ] Stack contents after each interrupt kind match the reference byte by byte (B bit per kind).
- [ ] Each interrupt costs 7 cycles.
- [ ] Power-up state matches the reference table.
- [ ] Known gaps (polling delay, hijacking) listed in `docs/architecture.md`.
- [ ] 100% branch coverage; rubocop clean.

## References

- CPU interrupts — https://www.nesdev.org/wiki/CPU_interrupts
- CPU power up state — https://www.nesdev.org/wiki/CPU_power_up_state
- Status flags (the B flag) — https://www.nesdev.org/wiki/Status_flags#The_B_flag
- NMI — https://www.nesdev.org/wiki/NMI
- IRQ — https://www.nesdev.org/wiki/IRQ
