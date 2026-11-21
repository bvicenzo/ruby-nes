# 20 — Mapper MMC1

**Status:** done (2026-11-21)

**Depends on:** 19

## Goal

Mapper 1 (MMC1), the first mapper with an internal state machine. It opens Zelda, Metroid, Mega Man 2 and the
multi-test builds of blargg's suites.

## Context

From the MMC1 page (references below; the SxROM page redirects to it):

- **Serial port.** "the CPU writes five times with bit 7 clear and one bit of the desired value in bit 0". "On the
  first four writes, the MMC1 shifts bit 0 into a shift register. On the fifth write, the MMC1 copies bit 0 and the
  shift register contents into an internal register selected by bits 14 and 13 of the address" (`$8000` control,
  `$A000` CHR bank 0, `$C000` CHR bank 1, `$E000` PRG bank); "Only on the fifth write does the address matter".
  "After the fifth write, the shift register is cleared automatically".
- **Reset.** A write with bit 7 set "clears the shift register to its initial state" and writes Control with
  `Control OR $0C` (PRG mode 3); "The CHR bank mode and nametable arrangement are not altered."
- **Consecutive-cycle writes.** "When the serial port is written to on consecutive cycles, it ignores every write
  after the first", which happens with read-modify-write instructions. "This restriction only applies to the data
  being written on bit 0; the bit 7 reset is never ignored." Bill & Ted's Excellent Adventure resets with `INC` on a
  ROM byte `$FF` and needs the `$00` written on the next cycle ignored (so a reset counts as the first write);
  Shinsenden sets bit 7 on the second write of `RRA abs,X` and crashes if that reset is ignored.
- **Control** (`CPPMM`): nametable 0 one-screen A, 1 one-screen B, 2 vertical mirroring, 3 horizontal mirroring; PRG
  mode 0/1 switch 32 KiB at `$8000` ignoring the bank's low bit, 2 fix the first bank at `$8000` and switch `$C000`,
  3 fix the last bank at `$C000` and switch `$8000`; CHR mode 0 one 8 KiB bank, 1 two 4 KiB banks.
- **CHR bank 0**: "Select 4 KiB or 8 KiB CHR bank at PPU $0000 (low bit ignored in 8 KiB mode)". **CHR bank 1**:
  "Select 4 KiB CHR bank at PPU $1000 (ignored in 8 KiB mode)".
- **PRG bank** (`RPPPP`): bits 0-3 "Select 16 KiB PRG-ROM bank (low bit ignored in 32 KiB mode)"; on the MMC1B bit 4
  is PRG RAM "0 = enabled, 1 = disabled"; iNES mapper 1 is the MMC1B ("Mapper 1 is used if the revision is not known
  or irrelevant", mapper 155 is the MMC1A).
- **SUROM** (512 KiB PRG): CHR bank 0 bit 4 "Select 256 KiB PRG-ROM bank", and the outer bank "applies to all the
  PRG area, including the normally "fixed" bank"; CHR bank 1 bit 4 is the same, "ignored in 8 KiB mode"; in 4 KiB
  mode the bits in both registers "must be set to the same values".
- **Power-up.** The MMC1 "seems to reliably power on in the last bank" (other tests found this "fragile"); PRG mode 2
  "doesn't seem to occur randomly on power-up".
- The CPU's read-modify-write double write was missing (plan 06, decision 5; `docs/architecture.md` Known gaps): "first
  [write] the original value back to memory" (Instruction reference) for `ASL`, `LSR`, `ROL`, `ROR`, `INC`, `DEC`,
  and "Read-Modify-Write instructions write unmodified data, then modified" (6502_cpu.txt) for the unofficial combos
  `SLO`, `RLA`, `SRE`, `RRA`, `DCP`, `ISB` (`Cpu::Instructions::ReadModifyWriteCombos`, plan 09).
- `Mappers::Base` (plan 19, decision 1) reads PRG ROM through two 16 KiB windows, which fit MMC1's 16/32 KiB modes as
  they are; CHR was one 8 KiB window.
- `Cpu#step` charges an instruction's base cycles before running it (plan 12, decision 1), so both writes of a
  read-modify-write instruction see the same `Cpu#cycles`; two separate store instructions are at least 4 cycles apart.

## Scope

In: the CPU's read-modify-write double write, the serial interface, all control modes, PRG RAM enable, the
consecutive-write rule, SUROM's 512 KiB PRG (selected by PRG size), two 4 KiB CHR windows in the base.

Out: the other variants' PRG RAM banking (SOROM, SXROM, SNROM's disable bit; backlog unless a game needs it), the
MMC1A (mapper 155), NES 2.0 submappers.

## Decisions

Settled with the user on 2026-11-20.

1. **The board gets the CPU as its clock.** `Mappers::Base#cpu=` (every board takes it, only MMC1 uses it); the
   `Console` wires `mapper.cpu = @cpu` as it does for `PpuRegisterSync`, and `Mmc1` hands `@cpu.cycles` to its serial
   port. Reason: no device interface changes; the plan's first idea (the bus passes the cycle on every write) changed
   every device's signature on the hot path, and `CpuBus` does not know the cycle.
2. **A write less than 2 cycles after the previous one is ignored, unless it is a reset; every write, ignored or
   reset, becomes "the previous one".** With the cycles charged before the instruction both writes of a
   read-modify-write differ by 0; with a per-access model they would differ by 1; either way under 2. Mesen2's
   `MMC1.h` uses the same threshold.
3. **The read-modify-write double write is added to the CPU for all 12 instructions** through one private step that
   writes the original byte, then the modified one, and returns the modified one (no block, no allocation). Its
   hardware side effect is kept: a read-modify-write on `$2007` increments the VRAM address twice. The Known gaps row
   goes away.
4. **Power-up: Control is `$0C`** (as after a reset: PRG mode 3, CHR mode 0, nametable 0, one-screen lower), the other
   registers 0, PRG RAM enabled; the header's mirroring is ignored, MMC1 controls it. A convention backed by "reliably
   power on in the last bank"; Mesen2 starts Control at its power-on byte OR `$0C`.
5. **The base reads CHR through two 4 KiB windows** (`$0000-$0FFF`, `$1000-$1FFF`), each wrapped by the number of
   4 KiB banks; CNROM selects both halves of its 8 KiB bank. Plan 21 refines them to 1 KiB. The `ppu_read` cost is
   measured before and after with a headless frame run (`rake bench:cpu` does not touch the PPU) and recorded in
   `docs/benchmarks.md`.
6. **PRG RAM is 8 KiB, enabled by PRG bank bit 4 clear** (MMC1B); disabled, `$6000-$7FFF` is open bus for reads and
   ignores writes.
7. **SUROM's outer bank comes from CHR bank 0 bit 4, only when PRG ROM is 512 KiB**, in both CHR modes (the page asks
   for both registers to match in 4 KiB mode and recommends 8 KiB mode). Other sizes use the bit for CHR only.
8. **The four multi-test builds enter the manifest.** Those that pass become `slow: true` examples of
   `Blargg::Runner#run`; the others are recorded in `docs/test-roms.md` with the reason. `MMC1_A12/mmc1_a12.nes` is
   interactive (no automatic result) and `instr_timing` needs the APU (plan 22): both are only noted.
9. **Mode 3 fixes the last bank of the PRG ROM when it is smaller than 256 KiB**, `min(outer + 15, last bank)`, rather
   than bank 15 wrapped by the bank count. Added after the review: the two agree on every power-of-two size, but
   `cpu_interrupts.nes` has 80 KiB (five banks), where bank 15 wraps to bank 0; the base already shows the file's last
   bank at `$C000` out of the box.

## Tasks

- [x] Specify and test the CPU's read-modify-write double write for the 12 instructions.
- [x] Specify and test the base's two 4 KiB CHR windows, the runtime PRG RAM enable and `cpu=`; adapt CNROM; measure
      the CHR window cost.
- [x] Specify and test `Mappers::Mmc1::SerialPort` (five writes, reset, consecutive-cycle ignore).
- [x] Specify and test `Mappers::Mmc1`: register selection, each PRG mode, CHR mode and mirroring value, PRG RAM
      enable/disable, SUROM's outer bank, power-up state.
- [x] Register it in `Mappers.build`; wire the CPU into the board in `Console`.
- [x] Add the test ROMs needing mapper 1: `instr_test-v5/all_instrs.nes`, `instr_test-v5/official_only.nes`,
      `ppu_vbl_nmi/ppu_vbl_nmi.nes`, `cpu_interrupts_v2/cpu_interrupts.nes` (results in `docs/test-roms.md`).
- [x] Update `docs/architecture.md` (mapper interface and base, board table, known gaps, decisions log),
      `docs/GLOSSARY.md`, `docs/test-roms.md`, `docs/benchmarks.md`.

## Acceptance criteria

- [x] Every register field (mirroring ×4, PRG modes, CHR modes, PRG RAM enable, SUROM's outer bank) is a spec leaf;
      so are the reset and the consecutive-write rule, including "the bit 7 reset is never ignored".
- [x] The double write exists for the 12 read-modify-write instructions; nestest and every ROM that passed still pass.
- [x] Every ROM in the manifest that needs MMC1 passes (or its failure is recorded with the reason).
- [x] Optional: a game the user owns boots to gameplay — not applicable: `roms/` only holds SMB3 (mapper 4).
- [x] The CHR window cost is measured and recorded.
- [x] 100% branch coverage; rubocop clean; `SLOW=1 bundle exec rake` green (the windowed backend specs
      excluded in the session, which has no display; they are unchanged).

## What was done

- The CPU's read-modify-write double write: `Cpu#write_modified` writes the original byte, then the modified one, for
  the six official instructions and the six unofficial combos; Known gaps loses the row, gains the double OAM DMA.
- `Mappers::Base`: CHR through two 4 KiB windows, `select_whole_prg_bank`/`select_whole_chr_bank` and `last_prg_bank`
  (AxROM, CNROM and MMC1 use them), PRG RAM switchable at runtime (`enable_prg_ram`), `cpu=` for every board, wired
  by `Console`. The CHR window costs about 5% of headless frames under YJIT, nothing measurable under ZJIT or without a
  JIT (`docs/benchmarks.md`).
- `Mappers::Mmc1::SerialPort` (five writes low bit first, the reset, writes under 2 cycles apart ignored, the reset
  never) and `Mappers::Mmc1` (mapper 1): the four registers, mirroring, PRG modes 0-3, CHR modes, PRG RAM off with PRG
  bank bit 4, SUROM's outer bank, power-up Control `$0C`; `Bits.bit_field` and `Bits.bit_at`.
- Specs: `Mmc1Programmer` (writes registers as a program does, standing in for the CPU's clock) and
  `Cartridges.numbered_banks`; `Cartridges.with_program` takes a mapper number.
- Test ROMs: `all_instrs` and `official_only` pass (slow examples of `Blargg::Runner#run`); `ppu_vbl_nmi` fails test 10
  and `cpu_interrupts` test 1, as their single builds (`docs/test-roms.md`).
- `docs/architecture.md`: the base and board table, the layout, decisions 48-50, Known gaps; `docs/GLOSSARY.md`: MMC1,
  serial port, SxROM/SUROM. Plan 21 notes the 4 KiB CHR windows and the whole-bank helpers.
- Independent review: CNROM's second CHR window and SUROM's mode 2 got leaves, mode 3's last bank follows a PRG ROM that
  is not a power of two (decision 9), `@cpu` starts as nil, the whole-bank helpers replaced four copies, `Bits.bit_at`
  replaced inline bit arithmetic in the specs, and names, comments and docs were fixed. Not applied: a guard in
  `enable_prg_ram` for boards without PRG RAM (no board calls it; the branch could not be covered).

## References

- MMC1 (also the SxROM board table) — https://www.nesdev.org/wiki/MMC1
- Instruction reference (read-modify-write double write) — https://www.nesdev.org/wiki/Instruction_reference
- 6502_cpu.txt (read-modify-write cycles) — https://www.nesdev.org/6502_cpu.txt
- Mesen2 MMC1 (consecutive-write threshold, power-up Control) —
  https://github.com/SourMesen/Mesen2/blob/master/Core/NES/Mappers/Nintendo/MMC1.h
