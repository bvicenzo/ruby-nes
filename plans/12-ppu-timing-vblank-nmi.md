# 12 — PPU timing, VBlank/NMI and the console loop

**Depends on:** 07, 11

## Goal

Make time pass: the PPU dot/scanline counters, the VBlank flag, NMI generation, the odd-frame skipped dot, and a
`Console` that runs CPU and PPU together frame by frame. Then run blargg's CPU instruction tests, which need VBlank.

## Context

NTSC frame: 262 scanlines × 341 dots.

| Scanlines | Phase |
|---|---|
| 0–239 | visible |
| 240 | post-render (idle) |
| 241–260 | VBlank; flag set at scanline 241 dot 1 (NMI here if enabled) |
| 261 (−1) | pre-render; VBlank, sprite 0 hit and overflow cleared at dot 1 |

On odd frames with rendering enabled, the pre-render line is one dot shorter (dot 339 → next frame dot 0). Enabling
NMI in PPUCTRL while the VBlank flag is set triggers an NMI immediately. Reading `$2002` right at the moment VBlank is
set suppresses that frame's flag/NMI (race documented on the NMI page).

The console loop (clock model chosen in plan 01): step the CPU, advance the PPU 3 dots per CPU cycle, deliver NMI to
the CPU, stop at the end of each frame.

From plan 07: the CPU detects the NMI edge itself, so the PPU calls `cpu.nmi_line = asserted` (a boolean) whenever
its NMI output (VBlank flag and PPUCTRL's NMI enable) changes; `Cpu#step` services a pending NMI as a step of its own.
IRQ is a level the CPU receives (`cpu.irq_line =`), while mappers expose a predicate (`irq?`): the console combines
every source (`mapper.irq? || apu.irq?`, plans 21 and 22) and sets the line after each catch-up, or the CPU polls a
list of sources — decide here. `Console#reset` calls `Cpu#reset`, which returns its 7 cycles for the PPU and
discards a pending NMI; power-up is `Cpu.new` + `reset`.

The CPU gaps deferred to this plan (`docs/architecture.md`, Known gaps) are checked here once the PPU exists: dummy
reads (plan 05, `cpu_dummy_reads`), and the interrupt polling point, the `CLI`/`SEI`/`PLP` IRQ delay and interrupt
hijacking (plan 07, `cpu_interrupts_v2`). They depend on the clock model decision below.

## Scope

In: PPU `tick`, frame counter and frame-complete signal, VBlank/NMI, odd-frame skip, `Console#run_frame`,
`Console#reset`, the blargg result reader (`$6000` status, `$6001-$6003` signature, `$6004+` text) as a test helper.

Out: pixels (plan 13).

## Open decisions

- Whether the suppression/race cases are modelled now. With instruction-level catch-up they likely cannot be exact;
  recommendation: model what the clock model allows and document the rest.
- Who combines the IRQ sources into `Cpu#irq_line=`: the console after each catch-up, or the CPU polling a list of
  devices answering `irq?`. Recommendation: the console, so the CPU keeps one boolean per line.
- If `ppu_vbl_nmi` timing tests reveal the catch-up model is insufficient for later goals (SMB3, plan 21), switch to
  per-bus-access ticking here, before rendering is built on top. Decide with the numbers from the test run.

## Tasks

- [ ] Specify and test the counters (wrap, odd-frame skip with rendering on/off), VBlank set/clear, NMI edge.
- [ ] Specify and test `Console#run_frame` (returns after exactly one frame; CPU cycles per frame within the documented
      29 780/29 781).
- [ ] Blargg result reader in `spec/support/`, with specs on synthetic memory.
- [ ] Add `instr_test-v5` and `ppu_vbl_nmi` to the test ROM manifest (check each ROM's mapper with plan 03's loader;
      ROMs whose mapper is not implemented yet move to the acceptance of that mapper's plan).
- [ ] Add `cpu_dummy_reads` and `cpu_interrupts_v2` to the manifest; after the clock model decision, model the CPU
      gaps it makes reachable (dummy reads, interrupt polling point, `CLI`/`SEI`/`PLP` delay, hijacking) or record
      why each stays a gap.
- [ ] Teach `Debug::Tracer` (plan 08) about interrupts: `Cpu#step` takes a pending NMI or IRQ instead of the opcode
      (decision 14 of `docs/architecture.md`: "the tracer sees an interrupt as one step"), but `Tracer#line` still
      names the instruction at the program counter. Once the PPU raises NMI, a trace of a running game needs either
      an interrupt line from the tracer (asking the CPU's interrupt lines without consuming them) or a runner that
      pairs log lines with instruction steps only. Automation-mode nestest is unaffected (no interrupt source).
      The same applies to a jammed CPU (plan 09): `Cpu#step` runs nothing, but `Tracer#line` names the instruction at
      the program counter; show the halt instead.

## Acceptance criteria

- [ ] All `instr_test-v5` single ROMs whose mapper is implemented report "Passed".
      Besides the official opcodes they exercise every unofficial one except XAA, AHX, TAS, LAS and the jams
      (readme: "not tested"), including the unstable `$AB`, `$9C` and `$9E` that plan 09 implemented from
      approximate formulas (plan 09, decision 1): a failure there may mean a formula, not a bug. The first suspect
      is `$AB`'s magic constant: plan 09 uses $EE, the value "No More Secrets" advises for emulators (a C64 source),
      while NES emulators are said to use $FF (`A = X = imm`) with no primary source found; next, the Z and N of
      `$AB`, inferred from the Visual6502 note on `$8B`.
- [ ] `ppu_vbl_nmi` `01-vbl_basics` and `04-nmi_control` pass; the result of every other ROM in the suite is recorded
      in `docs/test-roms.md` with the reason for each failure.
- [ ] The nestest trace `PPU:` column now matches too (extend plan 08's comparison: `Debug::Tracer#line` prints the
      PPU scanline and dot, and `Nestest::Log` keeps the column instead of dropping it).
- [ ] The result of every `cpu_dummy_reads` and `cpu_interrupts_v2` ROM is recorded in `docs/test-roms.md`; the
      Known gaps rows of `docs/architecture.md` are updated to match.
- [ ] 100% branch coverage on the timing code; rubocop clean.

## References

- PPU frame timing — https://www.nesdev.org/wiki/PPU_frame_timing
- PPU rendering (scanline timeline) — https://www.nesdev.org/wiki/PPU_rendering
- NMI — https://www.nesdev.org/wiki/NMI
- PPU power up state — https://www.nesdev.org/wiki/PPU_power_up_state
- Cycle reference chart — https://www.nesdev.org/wiki/Cycle_reference_chart
- `instr_test-v5`, `ppu_vbl_nmi`, `cpu_dummy_reads`, `cpu_interrupts_v2` —
  https://github.com/christopherpow/nes-test-roms (each suite's `readme.txt`)
