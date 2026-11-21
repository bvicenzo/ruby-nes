# 19 — Simple mappers: UxROM, CNROM, AxROM

**Status:** done (2026-11-20)

**Depends on:** 04

## Goal

Three discrete-logic mappers that exercise the mapper interface with bank switching but no internal state machine,
and the shared board base they and NROM are built on.

## Context

| Mapper | Board | Behaviour | Example games |
|---|---|---|---|
| 2 | UxROM | write to `$8000-$FFFF` selects the 16 KiB PRG bank at `$8000`; `$C000` fixed to the last bank; CHR-RAM | Castlevania, Mega Man, Contra, DuckTales |
| 3 | CNROM | write to `$8000-$FFFF` selects the 8 KiB CHR bank; PRG fixed (16 or 32 KiB) | Gradius, Solomon's Key |
| 7 | AxROM | write selects a 32 KiB PRG bank (bits 0–2) and the single-screen nametable (bit 4); CHR-RAM | Battletoads, Marble Madness |

From the NESdev pages (references below):

- **UxROM**: "CPU $8000-$BFFF: 16 KB switchable PRG ROM bank"; "CPU $C000-$FFFF: 16 KB PRG ROM bank, fixed to the last
  bank"; bank select `$8000-$FFFF`, "(UNROM uses bits 2-0; UOROM uses bits 3-0)", and "Emulator implementations of
  iNES mapper 2 treat this as a full 8-bit bank select register, without bus conflicts." PRG RAM capacity: "None";
  mirroring fixed by solder pads.
- **CNROM**: "CPU $8000-$FFFF: 32 KiB unbanked PRG-ROM" (16 KiB with the SL pad); "PPU $0000-$1FFF: 8 KiB switchable
  window into 32 KiB CHR-ROM"; bank select `$8000-$FFFF`, CHR bank in bits 1-0 (bits 3-0 on the oversize board),
  bits 5-4 drive the security diodes, and "Emulators need not emulate the functionality of security diodes". "The
  original CNROM board is always subject to AND-type bus conflicts: the effective value is the value being written
  bitwise-AND'd with the PRG-ROM content at the address being written to"; "the only .NES files requiring the absence
  of bus conflicts have been mapper hacks to mapper 3".
- **AxROM**: "CPU $8000-$FFFF: 32 KB switchable PRG ROM bank"; "CHR capacity: 8 KB RAM"; "PRG RAM: None"; bank select
  `$8000-$FFFF` laid out `xxxM xPPP`: PPP "Select 32 KB PRG ROM bank", M "Select 1 KB VRAM page for all 4
  nametables". Bus conflicts on AMROM/AOROM only; "Submapper 0: Bus conflict behavior undefined, but emulators
  _shouldn't_ emulate bus conflicts". The Mirroring page: "For AxROM connect the output of a register (e.g. 74HC161) to
  CIRAM A10 (AxROM latches PRG D4)".
- **Bus conflict**: "both the CPU and the mask ROMs used in the NES era drive a 0 more strongly than a 1", so "an
  emulator should use the bitwise AND of the value from the CPU and the value from the ROM."
- None of the three pages describes the bank register's state at power-up.

The interface is `cpu_read(address, data_bus)` (return `data_bus` when the board does not drive the bus),
`cpu_write`, `ppu_read`, `ppu_write`, `mirroring`, `irq?` (docs/architecture.md). Since plan 11, `mirroring` answers
one of `:horizontal`, `:vertical`, `:single_screen_lower`, `:single_screen_upper`, `:four_screen`, and `PpuBus` asks it
on every nametable access, so AxROM only has to change what it returns. `irq?` stays `false` here; architecture
decision 25 replaces it with a wired-OR push in plan 21 or 22.

`cpu_dummy_reads.nes` (in the collection) is a CNROM board: header `$31`, 32 KiB of PRG ROM, 8 KiB of CHR ROM. It is
built with blargg's older shell, which does not write the "Output at $6000" protocol: it prints `Passed`, `Failed` or
`Error n` on screen through a text console whose tiles are ASCII codes, beeps the code, and ends in an endless loop.

## Scope

In: the three mappers, the shared base extracted from NROM and them, single-screen mirroring changes at runtime
(AxROM), bank number masking by ROM size, a screen-text report for `cpu_dummy_reads`.

Out: variants with oversize banks (UNROM 512, 512 KiB AxROM, mapper 185 CHR enable, CNROM PRG RAM of Hayauchi Super
Igo, UxROM PRG RAM of NES 2.0 homebrew), NES 2.0 submappers (backlog).

## Decisions

Settled with the user on 2026-11-20.

1. **`Mappers::Base` reads through a window table.** PRG ROM is seen through two 16 KiB windows
   (`@prg_rom[@prg_window_offsets[(address >> 14) & 1] + (address & 0x3FFF)]`) and CHR through one 8 KiB window
   (`@chr[@chr_bank_offset + address]`); a board only turns register writes into window offsets. By default the first
   16 KiB are at `$8000` and the last 16 KiB at `$C000`, which is NROM-128, NROM-256, CNROM and UxROM's fixed bank.
   Reason: one read path for every board, the shape MMC1 (16 KiB windows) uses as is and MMC3 refines (8 KiB / 1 KiB),
   as Mesen2's `BaseMapper` does. Its cost is measured with `rake bench:cpu` before and after (nestest is NROM).
2. **Bus conflicts are emulated on CNROM only** (the written value ANDed with the PRG ROM byte visible at the
   address). Reason: the pages quoted above — UxROM's emulator note, AxROM's submapper 0 advice, CNROM's "only mapper
   hacks" need their absence. NES 2.0 submappers stay in the backlog (the header does not read them).
3. **UxROM, CNROM and AxROM have no PRG RAM**: `$4020-$7FFF` answers the data bus. Reason: "PRG RAM capacity: None"
   on the three pages; the exceptions are variants out of scope. NROM keeps its 8 KiB (plan 04, decision 2) through
   the base's `prg_ram: true` (a flag since the review: the base only knows 8 KiB, so a size could not be wrong).
4. **`cpu_dummy_reads` runs automatically through `Blargg::ScreenReport`**: finished once a line of nametable 0 is a
   result, its code read from it (`Passed` 0, `Failed` 1, `Error n` n; nil before). `Console#ppu_bus` exposes the PPU
   bus to tooling, as `cpu_bus` does. Amended while implementing: the plan first meant to share
   `Blargg::LegacyReport`'s "JMP to itself" detection, but the shell's final loop is `sei / lda #0 / sta $2000 / jmp`
   (`$E60F-$E615`), not a JMP to itself. The result line is enough on its own: the shell prints it only on exit, and
   its console writes a line to the nametable whole, when the newline flushes it.
5. **Bank numbers are masked when the register is written** (off the hot path), modulo the number of banks of that
   size. The modulo is a convention: it equals what a ROM without the upper address lines does when the bank count is
   a power of two (every licensed board), and NESdev does not describe the other sizes. UxROM takes the whole byte
   (the 8-bit register of the emulator note), AxROM bits 2-0, CNROM the whole byte (the diode bits fall outside the
   mask on boards of up to 32 KiB of CHR, and need no emulation).
6. **Every register starts at 0** (bank 0, AxROM's lower screen): a convention, since no page gives the power-up
   state (Mesen2 uses a configurable "power-on byte").
7. **AxROM's bit 4 picks the screen**: 0 `:single_screen_lower`, 1 `:single_screen_upper`. It drives CIRAM A10
   (Mirroring page); the polarity is not on NESdev and comes from Mesen2 (`Core/NES/Mappers/Nintendo/AXROM.h`:
   `0x10` selects screen B). AxROM ignores the header's mirroring.
8. **Size checks only where the bank arithmetic needs them**: AxROM refuses PRG ROM that is not a multiple of 32 KiB;
   CNROM refuses PRG ROM other than 16 or 32 KiB (the SL/CL solder pads); NROM keeps its checks. Each raises
   `Mappers::InvalidCartridge` naming the size.
9. **No multi-mapper test ROM**: Holy Mapperel is not in the collection at the pinned commit (its tree was searched),
   so the criterion is recorded as not applicable. The optional own-game boot is skipped: `roms/` only holds SMB3.

## Tasks

- [x] Specify and test `Mappers::Base`: windows, PRG RAM present or absent, CHR ROM/RAM, header mirroring, `irq?`,
      the register hook.
- [x] Rebuild `Mappers::Nrom` on the base (sizes, 8 KiB PRG RAM).
- [x] Specify and test each mapper: bank selection, fixed bank, masking when the selected bank exceeds the ROM,
      mirroring (AxROM), bus conflict (CNROM).
- [x] Register them in `Mappers.build`.
- [x] Add `cpu_dummy_reads/cpu_dummy_reads.nes` (CNROM, mapper 3) to the manifest and run it through
      `Blargg::ScreenReport` (a context of `Blargg::Runner#run`, `slow: true`); `rake blargg:run` picks the report.
- [x] Check whether a freely distributable multi-mapper test ROM (e.g. "Holy Mapperel") is in the test ROM
      collection: it is not (decision 9).
- [x] Measure the window table with `rake bench:cpu` before and after.
- [x] Update `docs/architecture.md` (mapper interface and base, layout, known gaps, decisions log), `docs/GLOSSARY.md`
      (the board names, bank, bus conflict), `docs/test-roms.md`.

## Acceptance criteria

- [x] The base and all three mappers are specified and implemented; `Mappers.build` returns them by number.
- [x] Bus conflicts on CNROM only; bank masking and AxROM's single screen are spec leaves.
- [x] If available, the multi-mapper test ROM passes for mappers 0, 2, 3 and 7 — not available (decision 9).
- [x] `cpu_dummy_reads` passes, or its result is recorded in `docs/test-roms.md` with the reason.
- [x] The window table's cost is measured and recorded in `docs/benchmarks.md`.
- [x] 100% branch coverage; rubocop clean; `SLOW=1 bundle exec rake` green.

## What was done

- `Mappers::Base`: PRG ROM through two 16 KiB windows and CHR through one 8 KiB window, 8 KiB of PRG RAM on request
  (`prg_ram: true`), CHR ROM or 8 KiB of CHR RAM, header mirroring, `irq?` false, `write_register` for boards with
  registers and `select_prg_bank`/`select_chr_bank` wrapping banks by the memory size. `Mappers::Nrom` rebuilt on it
  (its size checks and PRG RAM); the plan 10 memory variants of the CPU benchmark ported to it.
- `Mappers::Uxrom` (mapper 2), `Mappers::Cnrom` (mapper 3, AND-type bus conflict, 16/32 KiB PRG check) and
  `Mappers::Axrom` (mapper 7, 32 KiB banks from bits 2-0, single screen from bit 4, PRG in 32 KiB units), registered
  in `Mappers.build`; `Bits.low_bits`.
- `cpu_dummy_reads` (CNROM) in the manifest and passing in 45 frames, read by `Blargg::ScreenReport` (the older
  shell's result line on nametable 0) through the new `Console#ppu_bus`; `rake blargg:run` picks the report.
- The window table measured in one session against the base commit: about 3% under YJIT and the interpreter, under 1%
  under ZJIT, below the 6% the base commit moved between rounds (`docs/benchmarks.md`).
- `docs/architecture.md`: the board base and its table, decisions 46 (window table) and 47 (bus conflicts on CNROM
  only), the mapper register timing gap; `docs/GLOSSARY.md`: NROM, UxROM, CNROM, AxROM, bank, bus conflict;
  `docs/test-roms.md`: the screen protocol and the result. Plans 20 and 21 note the window granularity.
- Decision 4 amended while implementing: the shell's final loop is not a JMP to itself, so the report reads only the
  result line.
- Independent review: the mapper register timing gap recorded; `ScreenReport#state` reduced to its two causes and
  error codes read in base 10; AxROM's screen leaves moved under `#mirroring`; `prg_ram:` became a flag; the bank
  modulo documented as a convention; AxROM's redundant bank count dropped and the window indices moved to the base;
  stale comments fixed. Not applied: an "Internal error" pattern (the shell prints `Failed` after it), a shared
  16/32 KiB size check (two copies), a report lookup in the rake task (three cases), spec builders for numbered banks.

## References

- UxROM — https://www.nesdev.org/wiki/UxROM
- CNROM — https://www.nesdev.org/wiki/CNROM
- AxROM — https://www.nesdev.org/wiki/AxROM
- Bus conflict — https://www.nesdev.org/wiki/Bus_conflict
- Mirroring (single screen, CIRAM A10) — https://www.nesdev.org/wiki/Mirroring
- Mapper list — https://www.nesdev.org/wiki/Mapper
- Mesen2 AxROM (bit 4 polarity) — https://github.com/SourMesen/Mesen2/blob/master/Core/NES/Mappers/Nintendo/AXROM.h
- `cpu_dummy_reads` source (shell, CNROM header) — https://github.com/christopherpow/nes-test-roms/tree/master/cpu_dummy_reads/source
