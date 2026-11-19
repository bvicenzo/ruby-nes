# 09 — CPU unofficial opcodes

**Status:** done (2026-11-18)

**Depends on:** 08

## Goal

Implement the 105 unofficial opcodes so the **entire** `nestest.log` matches (8991 lines) and `$0002`/`$0003` read
`$00`. Milestone M1.

## Context

The 105 opcodes outside the official set include:

- Stable and used by some games / tested by nestest: multi-byte `NOP`s with reads, `LAX`, `SAX`, `SBC $EB`, and the
  read-modify-write combos `DCP`, `ISB` (`ISC`), `SLO`, `RLA`, `SRE`, `RRA`.
- Immediate combos: `ANC`, `ALR` (`ASR`), `ARR`, `AXS` (`SBX`).
- Unstable (depend on chip/analog effects): `XAA`/`ANE`, `LAX #imm`, `AHX`/`SHA`, `SHX`, `SHY`, `TAS`, `LAS`.
- `JAM`/`KIL`/`STP` opcodes that "halt the CPU until reset" (CPU unofficial opcodes).

nestest's unofficial section (lines 5004-8991) uses only the reading NOPs, LAX, SAX, `SBC $EB`, DCP, ISB, SLO, RLA,
SRE and RRA. blargg's `instr_test-v5` (plan 12) also tests ANC, ALR, ARR, AXS, `$AB` (ATX, LAX #imm), `$9C` (SYA, SHY)
and `$9E` (SXA, SHX); its readme marks the other unstable opcodes "? = Inconsistent/unknown behavior, so not tested"
and the jams "X = Freezes CPU, so not tested".

## Scope

In: all 105 unofficial opcodes (decision 1), `JAM` as a halted state (decision 2), the unofficial marker in the
tracer, the whole log in the nestest tooling.

Out: the read-modify-write double write of the combos (the existing known gap, plan 20); dummy reads (plan 12).

## Decisions

Settled with the user on 2026-11-18.

1. **The seven unstable opcodes are implemented** (XAA, LAX #imm, AHX ×2, TAS, SHY, SHX, LAS) with their documented
   formulas, commented as approximate (6502_cpu.txt marks that part "not accurate"); no opcode raises. Each formula's
   source is looked up and cited in the unit's prose before its spec. Reason: `instr_test-v5` tests three of them, and
   a game that hits one should not crash the emulator.
2. **`JAM` puts the CPU in a jammed state**, exposed as `Cpu#jammed?`: every later `step` touches no bus, takes no
   interrupt and returns 2 cycles, so the console keeps advancing the PPU and APU; only `reset` clears it. Reason: the
   frontend can show it, and real hardware keeps clocking. **Technical debt:** no reference found gives the cycles of
   a jammed CPU nor whether NMI/IRQ act on it; both are conventions, recorded in `docs/architecture.md` § Known gaps
   and in a code comment, pending a deeper search (Visual6502, "No More Secrets").
3. **The dispatch's `else` is `JAM`:** 244 explicit `when`s plus `else jam`, commented with the 12 jam bytes. Reason:
   Ruby's branch coverage counts a `case`'s implicit `else`, which with 256 `when`s would be unreachable. The 12 jams
   are listed explicitly in `Cpu::Opcodes` and each has a `#step` spec row, so a forgotten `when` fails its own row.
4. **Unofficial marker:** `Cpu::Opcodes::Opcode` gains `official?` (default true); an `UNOFFICIAL` table holds the 105
   entries; `TABLE` takes `OFFICIAL[opcode] || UNOFFICIAL.fetch(opcode)`, so an incomplete table fails at load time.
   `Debug::Tracer` prints `*` in the column before the mnemonic, as nestest.log does, and loses plan 08's `???` branch
   (plan 08, decision 3) and `Cpu::UnknownOpcode` goes away.
5. **Mnemonics** follow the wiki's opcode matrix, except `ISB` (nestest.log's name; the trace compares mnemonics) and
   `JAM` (6502_cpu.txt: "Jams the machine"; the wiki's `STP` is the name of a real 65C02 instruction).
6. **Cycles** (Programming with unofficial opcodes): the read-modify-write combos take fixed counts with no page-cross
   cycle ("always have a page crossing penalty even if not crossing a page"): zero page 5, zero page,X 6, absolute 6,
   absolute,X and absolute,Y 7, (indirect,X) and (indirect),Y 8 — plain resolvers. LAX absolute,Y and (indirect),Y and
   NOP absolute,X add the page-cross cycle (`_for_read` resolvers). Immediate opcodes take 2 ("Column +0B ... has no
   extra cycles").

Settled during implementation:

7. **Unstable formulas** come from "No More Secrets" V0.95 (text extracted from the PDF of the csdb release): ANE
   `A = (A | CONST) & X & imm` and LAX #imm `A,X = (A | CONST) & imm` with the constants the document advises for
   emulators, $EF and $EE; SHA/SHX/SHY/TAS write the value ANDed with the base address's high byte plus one, and when
   the index crosses a page "the highbyte of the target address is incremented by one (as expected), and then ANDed
   with" the value, so the byte lands on the page it names; LAS `A,X,SP = {addr} & SP`. Z and N of ANE follow the
   result ("N and Z flags are set according to the result of XAA", Visual6502 wiki), and LAX #imm's are inferred
   from ANE's: no source states them for `$AB`. "No More Secrets" says both follow A before the instruction —
   recorded in Known gaps for plan 12 to settle with `instr_test-v5`.
   *Revised by plan 12 (2026-11-19):* LAX #imm uses $FF, not $EE: blargg's `instr_test-v5/03-immediate`, whose
   checksum comes from the console, passes only with $FF (it fails with $EE and $00).
8. **Instruction names:** `read_and_ignore` (reading NOPs), `jam`, `load_accumulator_and_index_x` /
   `store_accumulator_and_index_x` (LAX, SAX), `shift_left_then_or` and siblings for the combos,
   `and_then_copy_sign_to_carry` / `and_then_shift_right` / `and_then_rotate_right` / `and_index_x_then_subtract`
   (ANC, ALR, ARR, AXS), and spelled-out names for the unstable seven; constants avoid mnemonics
   (`INDEX_X_AND_OPERAND_MAGIC_CONSTANT`, `OPERAND_LOAD_MAGIC_CONSTANT`).
9. **Dispatch lint:** the unofficial NOPs, ANC and `SBC $EB` repeat official bodies; `Lint/DuplicateBranch` is
   disabled on that `case` alone and `Metrics/ModuleLength` on `Dispatch` (architecture decisions 9 and 18).

## What was done

- `Cpu::Opcodes`: all 256 entries, `Opcode#official?` and the `UNOFFICIAL` table; `TABLE` fails at load time if a
  byte is missing. `Cpu::UnknownOpcode` and the tracer's `???` branch are gone.
- Instructions: LAX and SAX (`LoadStore`), `read_and_ignore` and `jam` (`ControlFlow`), and three new mixins:
  `ReadModifyWriteCombos` (SLO, RLA, SRE, RRA, DCP, ISB), `ImmediateCombos` (ANC, ALR, ARR, AXS, reusing
  `and_with_accumulator` and the accumulator shifts) and `Unstable` (ANE, LAX #imm, SHA, SHX, SHY, TAS, LAS).
- `Cpu#step`/`Dispatch`: 244 `when`s plus `else jam`; `Cpu#jammed?`, a jammed step costs 2 cycles and touches nothing,
  `reset` releases it. One `#step` spec row per opcode, plus page-cross rows.
- `Debug::Tracer` marks unofficial opcodes with `*`; `Nestest::Log.lines` keeps the whole log,
  `Nestest::Runner#unofficial_result` reads `$0003`, `rake nestest:diff` prints
  "All 8991 lines match; $0002 = $00, $0003 = $00". The full log matched on the first run: no CPU bug was found.
- `docs/architecture.md`: layout, decisions 16-18, Known gaps (jammed CPU, unstable opcodes, the combos' double
  write); `docs/GLOSSARY.md`: JAM, magic constant, RDY. Plans 12 and 20 got notes. 1100 examples, 100% line and
  branch coverage. One independent code review; its accepted follow-ups: stronger specs (AXS keeps V, page-cross
  rows for the unstable stores, one jammed context per interrupt line), ImmediateCombos reuse, named ARR bits, stale
  comments, the Visual6502 reference and the `$AB` caveats. Not applied: shared helpers for the combos' bodies (noted
  for plan 20), deriving `official: false` once, hoisting the runner spec's nestest setup.

## Tasks

- [x] `Cpu::Opcodes`: `Opcode#official?`, the `UNOFFICIAL` table, a complete `TABLE`.
- [x] Instructions, test first: LAX and SAX (`LoadStore`); reading NOPs and `jam` (`ControlFlow`); DCP, ISB, SLO,
      RLA, SRE, RRA (new `ReadModifyWriteCombos`); ANC, ALR, ARR, AXS (new `ImmediateCombos`); XAA, LAX #imm, AHX,
      TAS, SHY, SHX, LAS (new `Unstable`).
- [x] `Cpu#step` and `Dispatch`: one spec row per unofficial opcode; the jammed state; `reset` clears it.
- [x] `Debug::Tracer`: the `*` marker; the `???` branch removed.
- [x] `Nestest::Log.lines` (the whole log, marker kept) replaces `official_lines`; `Nestest::Runner#unofficial_result`
      (`$0003`); the nestest contexts cover the whole log; `rake nestest:diff` reports both result bytes.
- [x] `docs/architecture.md` (layout, decisions log, known gaps) and `docs/GLOSSARY.md`; plan 12 notes which
      unofficial opcodes `instr_test-v5` exercises.

## Acceptance criteria

- [x] The full `nestest.log` (8991 lines) matches in PC, bytes, marker, mnemonic, A, X, Y, P, SP and CYC.
- [x] `$0002` and `$0003` are `$00` at the end of the run.
- [x] All 256 opcodes have a table entry; none raises; `Cpu::UnknownOpcode` is gone.
- [x] `JAM` behaviour is specified and implemented as decided, with the debt in Known gaps.
- [x] 100% branch coverage on the CPU, the tracer and the nestest tooling; rubocop clean; `bundle exec rake` green.

Note: blargg's `instr_test-v5` suite waits on the PPU's VBlank flag before running, so it becomes an acceptance
criterion of plan 12, not of this plan.

## References

- CPU unofficial opcodes (opcode matrix, names) — https://www.nesdev.org/wiki/CPU_unofficial_opcodes
- Programming with unofficial opcodes (semantics, cycles) — https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes
- 6502_cpu.txt (bus cycles, unstable formulas, jams) — https://www.nesdev.org/6502_cpu.txt
- "No More Secrets" (detailed unofficial opcode document) — https://csdb.dk/release/?id=198357
- Visual6502 wiki, opcode $8B (XAA/ANE flags) — https://www.nesdev.org/wiki/Visual6502wiki/6502_Opcode_8B_(XAA,_ANE)
- instr_test-v5 readme (which opcodes it tests) —
  https://github.com/christopherpow/nes-test-roms/blob/master/instr_test-v5/readme.txt
