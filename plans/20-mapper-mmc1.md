# 20 — Mapper MMC1

**Depends on:** 19

## Goal

Mapper 1 (MMC1), the first mapper with an internal state machine. It opens Zelda, Metroid, Mega Man 2 and many test
ROMs.

## Context

- Registers are written serially: each write to `$8000-$FFFF` shifts bit 0 into a 5-bit shift register; the fifth
  write commits the value to the register chosen by address bits 13–14 (`$8000` control, `$A000` CHR bank 0, `$C000`
  CHR bank 1, `$E000` PRG bank).
- A write with bit 7 set resets the shift register and sets the control register's PRG mode to 3.
- Control: mirroring (0 one-screen lower, 1 one-screen upper, 2 vertical, 3 horizontal), PRG mode (bits 2–3: 32 KiB,
  fix first bank at `$8000`, fix last bank at `$C000`), CHR mode (bit 4: 8 KiB or two 4 KiB banks).
- PRG bank register bit 4 disables PRG-RAM (on most revisions).
- Writes on consecutive CPU cycles (read-modify-write instructions) are ignored after the first — a real quirk some
  games depend on. The CPU does not produce them yet: plan 06 (decision 5) leaves the read-modify-write double write
  ("first [write] the original value back to memory") out, listed in `docs/architecture.md` Known gaps. This plan must
  add it to the CPU (spec first) before the consecutive-cycle rule can be tested end to end. Plan 09 added six more
  read-modify-write instructions that need it too, the unofficial combos in `Cpu::Instructions::ReadModifyWriteCombos`
  (`SLO`, `RLA`, `SRE`, `RRA`, `DCP`, `ISB`); their bodies repeat the official ones' modify step, so a shared
  "modify memory, return the new byte" step (one place for the double write) is worth extracting then.
- Board variants (SNROM, SOROM, SUROM, SXROM) reuse CHR bank bits for PRG-RAM banking or 512 KiB PRG.

## Scope

In: the serial interface, all control modes, PRG-RAM enable, the consecutive-write rule, SUROM's 512 KiB PRG
(selected by PRG size).

Out: the other variants' PRG-RAM banking (backlog unless a game needs it).

## Open decisions

- How the mapper learns about "consecutive cycles": the CPU passes the current cycle count to writes, or the console
  exposes it. Recommendation: the bus passes the CPU cycle count on writes (also needed for MMC3 timing analysis).

## Tasks

- [ ] Specify and test the shift register (five writes, reset bit, consecutive-cycle ignore).
- [ ] Specify and test each PRG mode, CHR mode and mirroring value; PRG-RAM enable/disable.
- [ ] Add the test ROMs needing mapper 1 (checked in plan 12 from their headers): `instr_test-v5/all_instrs.nes`,
      `instr_test-v5/official_only.nes`, `ppu_vbl_nmi/ppu_vbl_nmi.nes` and `cpu_interrupts_v2/cpu_interrupts.nes`, the
      multi-test builds of suites whose single ROMs plan 12 ran (results in `docs/test-roms.md`).

## Acceptance criteria

- [ ] Every register field above is a spec leaf.
- [ ] Every ROM in the manifest that needs MMC1 passes (or its failure is recorded with the reason).
- [ ] Optional: a game the user owns boots to gameplay.
- [ ] 100% branch coverage; rubocop clean.

## References

- MMC1 — https://www.nesdev.org/wiki/MMC1
- SxROM board variants — https://www.nesdev.org/wiki/SxROM
