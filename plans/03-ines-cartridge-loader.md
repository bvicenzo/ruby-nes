# 03 — iNES cartridge loader

**Depends on:** 01

## Goal

Read a `.nes` file into an immutable `Cartridge` (header fields + PRG-ROM + CHR-ROM/CHR-RAM size + trainer), with
clear errors for files that are not valid iNES images.

## Context

iNES layout: 16-byte header, optional 512-byte trainer, PRG-ROM (16 KiB units), CHR-ROM (8 KiB units; `0` means the
board has 8 KiB of CHR-RAM instead).

Header:

| Byte | Meaning |
|---|---|
| 0–3 | `"NES"` + `$1A` |
| 4 | PRG-ROM size in 16 KiB units |
| 5 | CHR-ROM size in 8 KiB units (0 → CHR-RAM) |
| 6 | bit 0 mirroring (0 horizontal, 1 vertical), bit 1 battery, bit 2 trainer, bit 3 four-screen, bits 4–7 mapper low nibble |
| 7 | bits 2–3 = `0b10` → NES 2.0; bits 4–7 mapper high nibble |
| 8–15 | iNES 1.0: mostly unused; NES 2.0: extended fields |

Super Mario Bros. 3 (USA) (Rev 1), as read on 2026-11-17: `4E 45 53 1A 10 10 40 00 …` → 256 KiB PRG, 128 KiB CHR,
mapper 4, horizontal mirroring, no battery, no trainer, iNES 1.0; file size 393 232 bytes.

## Scope

In:

- `Cartridge::Header` (value object, `Data.define`) parsed from the 16 bytes.
- `Cartridge::Loader` reading a path or a byte string, returning `Cartridge`.
- NES 2.0 *detection* (flagged on the header); only the iNES 1.0 subset of fields is interpreted.
- Errors: not iNES (bad magic), truncated file (declared sizes exceed file length).

Out: mapper behaviour (plan 04 onward), NES 2.0 extended fields (backlog).

## Open decisions

- Archaic iNES headers with garbage ("DiskDude!") in bytes 7–15: ignore byte 7's mapper nibble when bytes 12–15 are
  non-zero (common emulator heuristic) or trust the header? Recommendation: apply the heuristic, it is documented on
  the iNES page.
- Trailing bytes beyond the declared sizes: accept silently or warn? Recommendation: accept.

## Tasks

- [ ] Describe the header behaviour in prose → `specify-behavior` → `write-tests` (build headers from byte literals in
      specs, no ROM files needed).
- [ ] Implement `Header`, `Loader`, `Cartridge`, error classes under `Ruby::Nes::Cartridge`.
- [ ] One `:test_rom`-style integration example (tag `:local_rom`, skipped when `roms/smb3.nes` is absent) that loads
      SMB3 and checks the values above.

## Acceptance criteria

- [ ] Every header bit listed above is covered by a spec leaf (including both mirroring values, battery, trainer
      offset, four-screen, mapper nibble combination, CHR-RAM case, NES 2.0 detection).
- [ ] Bad magic and truncated files raise distinct, named errors with a message naming the problem.
- [ ] Loading `roms/smb3.nes` yields mapper 4, PRG 262 144 bytes, CHR 131 072 bytes, horizontal mirroring, no
      battery.
- [ ] 100% branch coverage on the loader and header; rubocop clean.

## References

- iNES — https://www.nesdev.org/wiki/INES
- NES 2.0 — https://www.nesdev.org/wiki/NES_2.0
- Mirroring — https://www.nesdev.org/wiki/Mirroring
- Mapper list — https://www.nesdev.org/wiki/Mapper
