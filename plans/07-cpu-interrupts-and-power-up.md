# 07 — CPU interrupts and power-up

**Status:** done (2026-11-18)

**Depends on:** 06

## Goal

Reset, NMI, IRQ and BRK with correct vectors, stack contents, flag handling and cycle cost; and a documented power-up
state.

## Context

Vectors ([CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts)): NMI `$FFFA`, Reset `$FFFC`, IRQ/BRK `$FFFE`
(little-endian). The NMI/IRQ sequence is seven ticks (§ IRQ and NMI tick-by-tick execution): push PC high, PC low, P
(B clear for NMI/IRQ, set for BRK; bit 5 set — [Status flags](https://www.nesdev.org/wiki/Status_flags#The_B_flag)),
set `I`, load PC from the vector.

- NMI is edge-sensitive: the CPU's edge detector sees the line go active and the internal signal "stays high until the
  NMI has been handled". `I` does not mask it ("NMI, BRK, and reset are not affected").
- IRQ is level-sensitive (mapper, APU frame counter, DMC); ignored while `I` is set.
- "If both an NMI and an IRQ are pending at the end of an instruction, the NMI will be handled".
- `RTI` restores P (ignoring B and bit 5) and PC, and "affects IRQ inhibition immediately". `CLI`/`SEI`/`PLP` change
  `I` after polling, so they delay IRQ by one instruction (not modelled, decision 1).
- Reset "goes through the same sequence, but suppresses writes, decrementing the stack pointer thrice without
  modifying memory": 7 cycles, `S -= 3`, `I` set, PC from `$FFFC`.
- Power-up ([CPU power up state](https://www.nesdev.org/wiki/CPU_power_up_state)): `A = X = Y = 0`, C, Z, D, V, N
  clear, `I` set, `S = $00 - 3 = $FD`, PC from `$FFFC`. The stored flags are `$04`; pushed by an interrupt (or shown by
  nestest's log) they read `$24`. After a reset A, X, Y and the other flags are unchanged.

So power-up is `Cpu.new` (every register zero, the state before the sequence) followed by `Cpu#reset`.

From plan 05: interrupts push PC with `Cpu::Stack#push_word` and P with `Cpu::Status#byte_pushed_by_interrupt`
(B clear, bit 5 set); `RTI` uses `Status#restore`, which already ignores bits 4 and 5.

## Scope

In: `Cpu#reset`, `Cpu#nmi_line=` (edge detected by the CPU), `Cpu#irq_line=` (level), polling between instructions in
`Cpu#step`, BRK sharing the interrupt sequence.

Out: who raises NMI/IRQ (PPU plan 12, mappers plan 21, APU plan 22); the quirks of decision 1.

## Decisions

Settled with the user on 2026-11-18.

1. **The `CLI`/`SEI`/`PLP` polling delay, interrupt hijacking and the branch polling quirk are deferred**, listed in
   `docs/architecture.md` Known gaps together with polling at the instruction boundary instead of the second-to-last
   cycle. Reason: all depend on timing inside an instruction, which the instruction-level catch-up (decision 1 of the
   architecture) does not have. Revisit with `cpu_interrupts_v2`.
2. **The interrupt lines are level setters: `Cpu#nmi_line=(asserted)` and `Cpu#irq_line=(asserted)`.** The CPU
   detects the NMI's rising edge and keeps it pending until serviced; IRQ is a level. Reason: the edge detector is in
   the CPU on hardware; enabling NMI in PPUCTRL during VBlank (plan 12) then needs no special case, a short pulse is
   not lost when the PPU calls the setter on every change, and several IRQ sources combine as
   `cpu.irq_line = first || second`.
3. **An interrupt is a `Cpu#step` of its own.** Before fetching an opcode, `step` services a pending NMI, or the IRQ
   when its line is asserted and `I` is clear, and returns 7; the handler's first instruction runs on the next step.
   Reason: lines raised while the console catches up after the previous instruction are seen in time, and the tracer
   (plan 08) sees an interrupt as one step.
4. **Reset costs 7 cycles** (the same sequence as NMI/IRQ). Reason: the CPU interrupts page above; it also gives
   nestest's initial `CYC:7`.
5. **`Cpu::InterruptLines` owns the lines** (settled during implementation, 2026-11-18): built with the CPU's
   `Status`, it has `nmi_line=`, `irq_line=` (booleans) and `acknowledge`, which returns the vector to take (NMI
   first, IRQ unless I is set) or nil and consumes the pending NMI; `Cpu::Interrupts` delegates the setters and
   `Cpu#step` only dispatches. I is read only when the IRQ line is asserted (tell, don't ask). Reason: specified
   inside `Cpu#step`, the NMI line history crossed with IRQ masking and the push sequence grew past 20 leaves; split,
   the edge/level/priority rules are 12 leaves and `step` adds 10. Cost: one method call per step, measured in plan 10.
6. **Reset discards a pending NMI and returns 7** (settled in the review, 2026-11-18). Reason: the NESdev pages say
   nothing about a pending NMI across reset; a handler running before the game's init code would be wrong, and the
   line levels stay with their devices (the PPU clears PPUCTRL on its own reset, plan 12). Returning the cycles
   like `Cpu#step` lets `Console#reset` advance the PPU by them. A modelling decision, not a hardware fact.

## What was done

- `Cpu::Interrupts`, included in `Cpu`: `reset` (`S -= 3` with no stack write, I set, PC from `$FFFC`, a pending NMI
  discarded, returns 7 cycles), the `nmi_line=`/`irq_line=` setters, and the sequence BRK, NMI and IRQ share
  (`enter_interrupt`). Power-up is `Cpu.new` + `reset`; the vectors are `Cpu::NMI_VECTOR`, `RESET_VECTOR`,
  `IRQ_VECTOR`.
- `Cpu::InterruptLines`, built with the CPU's `Status`: the NMI edge detector, the IRQ level, masking by I and NMI
  priority; `acknowledge` names the vector to take. `Cpu#step` takes that interrupt as a step of its own (7 cycles).
- `Bits.wrap_to_byte`, the first off-hot-path use of the `wrap-to-byte` idiom.
- `docs/architecture.md`: layout row, Known gaps (interrupt polling point, `CLI`/`SEI`/`PLP` delay, hijacking),
  decisions 13-15, decision 12 closed. `CLAUDE.md`: spec trees shrink only through code changes. Plans 08 and 12
  aligned; plan 12 now owns the deferred CPU gaps (`cpu_dummy_reads`, `cpu_interrupts_v2`) and the IRQ-source
  combination.
- 46 new examples (818 in all), 100% line and branch coverage. A diagnostic run of `nestest.nes` (not committed)
  gives `P:24 SP:FD CYC:7` after power-up, the log's first line.
- One independent code review, no correctness bug in the delivered scope. Applied: reset discards a pending NMI and
  returns its cycles (decision 6), `InterruptLines` reads I itself, discriminating push assertions (`$8123`, carry
  set) plus the stack pointer leaf, boolean-only setters documented, the deferred gaps and the IRQ combination moved
  into plan 12. Not applied: flattening the `InterruptLines` spec (depth mirrors the rules; see `CLAUDE.md`), a
  `Stack` method for the reset decrement, renaming `acknowledge`, a spec tying `INTERRUPT_CYCLES` to BRK's table row.

## Tasks

- [x] `Cpu#reset` in a new `Cpu::Interrupts` mixin: `S -= 3` with wrap and no stack write, `I` set, PC from `$FFFC`,
      7 cycles, A/X/Y and the other flags unchanged; a power-up context (`Cpu.new` + `reset`).
- [x] The shared interrupt sequence (push return address, push status byte, set `I`, load vector); BRK uses it, its
      existing specs stay green.
- [x] `nmi_line=`, `irq_line=` and polling in `Cpu#step`. Leaves for: NMI while `I` set (still taken), NMI line held
      (one NMI only), NMI line released and raised again (second NMI), IRQ while `I` set (not taken), IRQ line still
      asserted after RTI (taken again), pending NMI and IRQ at the same time (NMI wins).
- [x] `docs/architecture.md`: layout row, Known gaps, Decisions log; plans 08 and 12 aligned.

## Acceptance criteria

- [x] Stack contents after NMI, IRQ and BRK match the reference byte by byte (B per kind, bit 5 set); reset writes
      nothing to the stack.
- [x] NMI, IRQ, BRK and reset each cost 7 cycles.
- [x] `Cpu.new` + `reset` matches the power-up table; a soft reset keeps A, X, Y and every flag but `I`.
- [x] Leaves exist for the NMI edge, the IRQ level, masking, IRQ taken again after RTI and NMI priority.
- [x] Known gaps (polling delay, hijacking, branch polling, instruction-boundary polling) listed in
      `docs/architecture.md`.
- [x] 100% branch coverage; rubocop clean; `bundle exec rake` green.

## References

- CPU interrupts — https://www.nesdev.org/wiki/CPU_interrupts
- CPU power up state — https://www.nesdev.org/wiki/CPU_power_up_state
- Status flags (the B flag) — https://www.nesdev.org/wiki/Status_flags#The_B_flag
- NMI — https://www.nesdev.org/wiki/NMI
- IRQ — https://www.nesdev.org/wiki/IRQ
- `cpu_interrupts_v2` (the deferred quirks) — https://github.com/christopherpow/nes-test-roms
