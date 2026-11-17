# 19 — Simple mappers: UxROM, CNROM, AxROM

**Depends on:** 04

## Goal

Three discrete-logic mappers that exercise the mapper interface with bank switching but no internal state machine.

## Context

| Mapper | Board | Behaviour | Example games |
|---|---|---|---|
| 2 | UxROM | write to `$8000-$FFFF` selects the 16 KiB PRG bank at `$8000`; `$C000` fixed to the last bank; CHR-RAM | Castlevania, Mega Man, Contra, DuckTales |
| 3 | CNROM | write to `$8000-$FFFF` selects the 8 KiB CHR bank; PRG fixed (16 or 32 KiB) | Gradius, Solomon's Key |
| 7 | AxROM | write selects a 32 KiB PRG bank (bits 0–2) and the single-screen nametable (bit 4); CHR-RAM | Battletoads, Marble Madness |

Many of these boards have **bus conflicts**: the written value is ANDed with the ROM byte at the same address.

## Scope

In: the three mappers, single-screen mirroring changes at runtime (AxROM), bank number masking by ROM size.

Out: variants with oversize banks (UNROM 512 etc.).

## Open decisions

- Emulate bus conflicts (AND with ROM) or not? Recommendation: emulate for CNROM and UxROM per the wiki's guidance
  (submapper default), not for AxROM boards known to lack them; record the choice.

## Tasks

- [ ] Specify and test each mapper: bank selection, fixed bank, masking when the selected bank exceeds the ROM,
      mirroring (AxROM), bus conflict as decided.
- [ ] Register them in `Mappers.build`.
- [ ] Check whether a freely distributable multi-mapper test ROM (e.g. "Holy Mapperel") is in the test ROM collection;
      if so add it to the manifest.

## Acceptance criteria

- [ ] All three mappers are specified and implemented; `Mappers.build` returns them by number.
- [ ] If available, the multi-mapper test ROM passes for mappers 0, 2, 3 and 7.
- [ ] Optional: a game the user owns per mapper boots to gameplay.
- [ ] 100% branch coverage; rubocop clean.

## References

- UxROM — https://www.nesdev.org/wiki/UxROM
- CNROM — https://www.nesdev.org/wiki/CNROM
- AxROM — https://www.nesdev.org/wiki/AxROM
- Bus conflict — https://www.nesdev.org/wiki/Bus_conflict
- Mapper list — https://www.nesdev.org/wiki/Mapper
