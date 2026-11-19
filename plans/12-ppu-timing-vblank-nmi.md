# 12 — PPU timing, VBlank/NMI and the console loop

**Depends on:** 07, 11

**Status:** in progress (base 8977021)

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

The console loop (clock model chosen in plan 01, refined here by decision 1): step the CPU, advance the PPU 3 dots per
CPU cycle, deliver NMI to the CPU, stop at the end of each frame.

From plan 07: the CPU detects the NMI edge itself; `Cpu#step` services a pending NMI as a step of its own.
`Console#reset` calls `Cpu#reset`, which returns its 7 cycles for the PPU and discards a pending NMI; power-up is
`Cpu.new` + `reset`.

From plan 11: `Ppu` answers the `ppu_registers:` slot over a `PpuBus`; `$2002` returns bits 7–5 as 0 (no flag
exists yet) with bits 4–0 from the PPU I/O latch, and clears `w`. This plan adds the VBlank flag, its "reading
`$2002` clears it" leaf ("Reading PPUSTATUS will return the current state of this flag and then clear it", PPU
registers), and the writes to `$2000`, `$2001`, `$2005` and `$2006` ignored "until reaching the pre-render scanline"
after power and reset ([PPU power up state](https://www.nesdev.org/wiki/PPU_power_up_state): the internal reset
signal "is set on reset and cleared at the end of VBlank", i.e. at dot 1 of the pre-render scanline). The console
wires `CpuBus.new(mapper:, ppu_registers: …)` with `Ppu.new(bus: PpuBus.new(mapper:))`; OAM DMA is already inside
`CpuBus` and its stall comes back through `Cpu#step`.

Power-up facts (PPU power up state): "The PPU comes out of power and reset at the top of the picture" (scanline 0,
dot 0, consistent with nestest.log's `PPU:  0, 21` at `CYC:7`); "The VBL flag (PPUSTATUS bit 7) is random at power,
and unchanged by reset" (decision 8 picks clear at power).

Test ROM boards, read from each iNES header (2026-11-18): every `rom_singles` ROM of `instr_test-v5`, `ppu_vbl_nmi`,
`cpu_interrupts_v2` and `instr_misc`, and `ppu_open_bus.nes`, is NROM; `cpu_dummy_reads.nes` is CNROM (mapper 3,
plan 19); the multi-test builds (`instr_test-v5/all_instrs.nes`, `official_only.nes`, `ppu_vbl_nmi/ppu_vbl_nmi.nes`,
`cpu_interrupts_v2/cpu_interrupts.nes`) are MMC1 (plan 20). `cpu_interrupts_v2` ROMs 1, 3, 4 and 5 rely on the APU
frame IRQ (its readme: "It uses the APU's frame IRQ"), and `instr_misc/04-dummy_reads_apu` "Requires that APU
implement $4015 IRQ flag reading" (plan 22).

Blargg's result protocol (each suite's readme, "Output at $6000"): "The test status is written to $6000. $80 means the
test is running, $81 means the test needs the reset button pressed, but delayed by at least 100 msec from now.
$00-$7F means the test has completed and given that result code"; `$DE $B0 $61` is written to `$6001-$6003`; "All
text output is written starting at $6004, with a zero-byte terminator at the end".

## Scope

In: PPU frame timing (counters, frame number and parity, odd-frame skip), VBlank/NMI with the polling point, the
`$2002` read at (241, 0), the writes ignored after power and reset, register-access synchronisation, dummy reads of
the indexed addressing modes, `Console` (`new`, `step`, `run_frame`, `reset`), the tracer's PPU column and interrupt
and jam lines, the blargg result reader and runner as test helpers, the slow-ROM tag and its CI job.

Out: pixels (plan 13); IRQ sources and the IRQ line's new shape (decision 3, implemented by plans 21/22); the
`CLI`/`SEI`/`PLP` delay and interrupt hijacking (plan 22, where `cpu_interrupts_v2` becomes runnable); PPU I/O latch
decay (decision 9).

## Decisions

Settled with the user on 2026-11-18.

1. **Clock model: synchronise on register access** (upgrade path 1 of `docs/architecture.md`, Clock model).
   `Cpu#step` charges an opcode's base cycles before executing it, so during the instruction `Cpu#cycles` is the
   cycle the instruction ends on. Before any CPU access to `$2000-$3FFF`, the PPU catches up to the start of the
   instruction's last CPU cycle; after the step, the console catches it up to the end. Reason: with pure
   instruction-level catch-up, `ppu_vbl_nmi/04-nmi_control` test 11 ("Immediate occurence should be after NEXT
   instruction") cannot pass: `STA $2000` writes on its last cycle, after the CPU polled. Every non-read-modify-write
   instruction makes its data access on its last cycle ([6502_cpu.txt](https://www.nesdev.org/6502_cpu.txt)), so the
   sync puts reads and writes on the right dot; read-modify-write instructions on PPU registers are approximated.
   Cost: one call per PPU register access, none per instruction beyond the console's catch-up.
2. **NMI polling point.** The NMI edge carries the CPU cycle it happened on (the PPU's dot divided by 3). At the start
   of a step the CPU takes a pending NMI only if its edge came before the last cycle of the previous instruction:
   "the line status at the end of the second-to-last cycle" is what the poll sees
   ([CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts)); a later edge is taken one instruction later.
   `Cpu#nmi_line=` gains the cycle (name settled in TDD). Reason: decision 1 alone moves the write to the right dot
   but the CPU would still see it before the next instruction.
3. **IRQ sources combine as a wired-OR push.** Each source asserts and releases its own bit on a shared line (the
   open-collector IRQ line of the hardware); the CPU sees the line asserted while any bit is set. It replaces the
   mappers' `irq?` predicate. Recorded in `docs/architecture.md` and plans 21/22; the first plan with an IRQ source
   implements it. Reason: no per-instruction query (plan 11 measured a similar per-step query at about −8% under
   YJIT), and no source can assert in this plan (NROM never does).
4. **Dummy reads of the indexed modes are modelled**: absolute,X, absolute,Y and (indirect),Y read the address whose
   high byte is not yet fixed — on a page cross for reads, always for writes and read-modify-write instructions
   ([6502_cpu.txt](https://www.nesdev.org/6502_cpu.txt)). The other dummy reads (zero page indexed, implied, the
   stack) read RAM or the next program byte, never a register, and stay documented as not modelled. Reason:
   `instr_misc/03-dummy_reads` (NROM) checks them through `$2002`'s read side effect; the cost is measured with
   `rake bench:cpu`.
5. **`$2002` read race**: a read on dot (241, 0) returns the flag clear, and the flag is not set nor the NMI raised that
   frame ("Reading the flag on the dot before it is set (scanling 241, dot 0) causes it to read as 0 and be cleared",
   [PPU registers](https://www.nesdev.org/wiki/PPU_registers); "the flag is not set and the NMI is not generated for
   that frame", [PPU frame timing](https://www.nesdev.org/wiki/PPU_frame_timing)). NMI suppression by reads on the
   same dot or the next one stays a Known gap: the CPU has already latched the edge. `06-suppression`'s result is
   recorded.
6. **Slow test ROM runs.** Examples that run a blargg ROM are tagged `slow: true` and excluded by default; `SLOW=1`
   includes them. Criterion: CI always runs them (`SLOW=1`, under YJIT, in a job of their own on every push and pull
   request), and phase 5 of `implement-plan` runs `SLOW=1 bundle exec rake` before closing any plan that touches the
   CPU, the PPU, the console or a mapper. `rake blargg:run[rom]` prints a ROM's status and text, for debugging and
   for `docs/test-roms.md`. Reason: each ROM runs seconds to minutes of emulated time; the suite takes 5 s today.
7. **A frame ends when the PPU wraps to (0, 0)**; `Console#run_frame` steps until the PPU's frame number changes.
   Reason: the frame's dot count is then 89 342 (89 341 odd with rendering), as `docs/architecture.md` states.
8. **Power-up and reset.** `Ppu.new` is ready (writes accepted), so register specs stay simple; `Ppu#reset` opens the
   window of ignored writes and clears PPUCTRL, PPUMASK, `t`, fine `x`, `w`, the PPUDATA read buffer and the odd-frame
   flag (PPU power up state, "After Reset" column and the reset signal: "the VRAM address itself (V) is _not_
   cleared"). `Console.new` is the power-up: `Cpu#reset`, `Ppu#reset`, then the PPU catches up the 7 reset
   cycles. The VBlank flag is clear at power: a convention (the page says random).
9. **PPU I/O latch decay stays out**: `ppu_open_bus`'s result is recorded and the Known gap keeps its row.
10. **`LAX #imm` ($AB) uses the magic constant $FF** (settled during implementation, 2026-11-19, with the user):
    `instr_test-v5/03-immediate` fails with $EE (plan 09's choice, "No More Secrets"' advice) and $00 and passes with
    $FF; NESdev gives no constant. Plan 09's decision 7 carries a note.

## Tasks

- [x] `Ppu::FrameTiming`: counters (dot and scanline wrap, frame number, parity), odd-frame skip with rendering on and
      off, the (241, 1) and (261, 1) events, and the (241, 0) `$2002` read race (`#status_read`: it knows the
      position, so the next dot does not tell that VBlank started). Rendering is sampled at dot 339 of the pre-render
      scanline (the 3-4 dot delay of a PPUMASK write is a Known gap).
- [x] `Ppu::VerticalBlank`: the VBlank flag and the /NMI level (flag AND PPUCTRL bit 7), told to an `nmi_output` only
      when it changes; `#read` returns the flag as a boolean and clears it. The CPU cycle of the edge is stamped by
      the layer that owns the clock (the Ppu or the console), not here.
- [x] `Ppu`: `$2002` bit 7, `$2000` bit 7, `$2001` rendering bits, `reset` with the ignored writes, `catch_up`. The
      Ppu hears FrameTiming's events and VerticalBlank's `nmi_output_changed`, and tells
      `nmi_input.nmi_line_changed(asserted, cycle)` with the CPU cycle of the dot (`nmi_input:` keyword, or the writer
      the Console uses). Reset also clears t, fine x and the PPUDATA read buffer (`ScrollRegisters#reset`,
      `DataPort#clear_read_buffer`); an ignored write still loads the I/O latch, which is a bus, not a cleared
      register.
- [x] `Cpu`: base cycles charged before `execute`; `InterruptLines` takes the NMI at the polling point.
      `Cpu#nmi_line_changed(asserted, cycle)` replaces `nmi_line=`; `InterruptLines#acknowledge(cycle)` takes an NMI
      whose edge came before the previous instruction's last cycle (a second edge while pending keeps the first
      cycle); `Cpu.new` takes `cycles:` so specs can start at any cycle.
- [x] `Cpu::AddressingModes`: dummy reads of the indexed modes; measure with `rake bench:cpu`. About 2% under YJIT,
      nothing measurable under the interpreter or ZJIT (`docs/benchmarks.md`, 2026-11-19).
- [x] Register-access synchronisation in the `ppu_registers:` slot (`Console::PpuRegisterSync`).
- [x] `Console#run_frame` (exact frame dot count; CPU cycles per frame averaging 29 780.5 with rendering and 29 780⅔
      without), `Console.new`, `Console#step`, `Console#reset`.
- [x] Teach `Debug::Tracer` (plan 08) about the PPU and interrupts: the `PPU:` column; a line of its own when the next
      step takes an NMI or IRQ (asked without consuming it: decision 14 of `docs/architecture.md`, "the tracer sees
      an interrupt as one step"); and a jammed CPU (plan 09) shows the halt instead of the instruction at the program
      counter.
- [x] `Nestest::Log` keeps the PPU column; `Nestest::Runner.automation_mode` builds a `Console` (the CPU benchmark
      keeps stepping the CPU alone).
- [x] Blargg result reader and runner in `spec/support/`, with specs on synthetic memory; the real ROMs are contexts of
      the runner's entry point (`test_rom:`, `slow: true`).
- [x] Manifest: `instr_test-v5` and `ppu_vbl_nmi` singles, `instr_misc` singles 01–03, `cpu_interrupts_v2` singles,
      `ppu_open_bus`.
- [x] `SLOW` in `spec_helper`, `rake blargg:run`, the CI job, `implement-plan` phase 5.
- [x] `docs/test-roms.md` with every ROM's result; `docs/architecture.md` (clock model, Console, IRQ line, layout,
      decisions, Known gaps); `docs/GLOSSARY.md`.

## Acceptance criteria

- [x] All 16 `instr_test-v5` single ROMs report "Passed".
      Besides the official opcodes they exercise every unofficial one except XAA, AHX, TAS, LAS and the jams
      (readme: "not tested"), including the unstable `$AB`, `$9C` and `$9E` that plan 09 implemented from
      approximate formulas (plan 09, decision 1): a failure there may mean a formula, not a bug. The first suspect
      is `$AB`'s magic constant: plan 09 uses $EE, the value "No More Secrets" advises for emulators (a C64 source),
      while NES emulators are said to use $FF (`A = X = imm`) with no primary source found; next, the Z and N of
      `$AB`, inferred from the Visual6502 note on `$8B`. *Result:* `03-immediate` failed "AB ATX #n" with $EE and
      passes with $FF; Z and N from the result are confirmed (decision 10).
- [x] `ppu_vbl_nmi` `01-vbl_basics` and `04-nmi_control` pass; the result of every other ROM in the suite is recorded
      in `docs/test-roms.md` with the reason for each failure.
- [x] `instr_misc` `01-abs_x_wrap`, `02-branch_wrap` and `03-dummy_reads` pass.
- [x] The nestest trace `PPU:` column now matches too (`Debug::Tracer#line` prints the PPU scanline and dot, and
      `Nestest::Log` keeps the column instead of dropping it).
- [x] The result of every `cpu_interrupts_v2` single and of `ppu_open_bus` is recorded in `docs/test-roms.md`; the
      Known gaps rows of `docs/architecture.md` are updated to match.
- [x] A frame is exactly 89 342 dots (89 341 on odd frames with rendering enabled); CPU cycles per frame average
      29 780.5 with rendering enabled and 29 780⅔ without.
- [ ] 100% branch coverage on the timing code; rubocop clean; `SLOW=1 bundle exec rake` green; CI runs the slow ROMs.
      Verified locally: 529/529 branches, 162 files clean, 1456 examples with `SLOW=1`. The CI job `test-roms` is
      configured; it is checked on the first push.

## References

- PPU frame timing — https://www.nesdev.org/wiki/PPU_frame_timing
- PPU rendering (scanline timeline) — https://www.nesdev.org/wiki/PPU_rendering
- NMI — https://www.nesdev.org/wiki/NMI
- PPU registers — https://www.nesdev.org/wiki/PPU_registers
- PPU power up state — https://www.nesdev.org/wiki/PPU_power_up_state
- CPU interrupts (polling point) — https://www.nesdev.org/wiki/CPU_interrupts
- 6502_cpu.txt (cycle-by-cycle bus accesses, dummy reads) — https://www.nesdev.org/6502_cpu.txt
- Cycle reference chart — https://www.nesdev.org/wiki/Cycle_reference_chart
- `instr_test-v5`, `ppu_vbl_nmi`, `cpu_dummy_reads`, `cpu_interrupts_v2`, `instr_misc`, `ppu_open_bus` —
  https://github.com/christopherpow/nes-test-roms (each suite's `readme.txt`)
