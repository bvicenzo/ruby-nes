# 03 — iNES cartridge loader

**Status:** done (2026-11-18)

**Depends on:** 01

## Goal

Read a `.nes` file into an immutable `Cartridge` (header fields + PRG-ROM + CHR-ROM/CHR-RAM size + trainer), with
clear errors for files that are not valid iNES images.

## Context

iNES layout ([iNES](https://www.nesdev.org/wiki/INES)): 16-byte header, optional 512-byte trainer, PRG-ROM (16 KiB
units), CHR-ROM (8 KiB units; `0` means the board uses CHR-RAM instead). Some images carry more data after CHR-ROM
(PlayChoice INST-ROM and PROM, a 127- or 128-byte title).

Header:

| Byte | Meaning |
|---|---|
| 0–3 | `"NES"` + `$1A` |
| 4 | PRG-ROM size in 16 KiB units |
| 5 | CHR-ROM size in 8 KiB units (0 → CHR-RAM) |
| 6 | bit 0 mirroring (0 horizontal, 1 vertical), bit 1 battery, bit 2 trainer, bit 3 alternative nametable layout, bits 4–7 mapper low nibble |
| 7 | bit 0 VS Unisystem, bit 1 PlayChoice-10, bits 2–3 = `0b10` → NES 2.0; bits 4–7 mapper high nibble |
| 8–15 | iNES 1.0: byte 8 PRG-RAM size (not widely used), 9–10 rarely honoured, 11–15 padding; NES 2.0: extended fields |

Byte 6 bit 3 is not a plain "four-screen" flag: the iNES page names it *alternative nametable layout* and says its
meaning varies by mapper (four-screen on some MMC3 boards, one-screen/four-screen together with bit 0 on UNROM 512).
The header exposes the raw bit; each mapper interprets it.

Super Mario Bros. 3 (USA) (Rev 1), as read on 2026-11-17: `4E 45 53 1A 10 10 40 00 …` → 256 KiB PRG, 128 KiB CHR,
mapper 4, horizontal mirroring, no battery, no trainer, iNES 1.0; file size 393 232 bytes.

## Scope

In:

- `Cartridge::Header` (value object, `Data.define`) parsed from the 16 bytes.
- `Cartridge::Loader` reading a path or a byte string, returning `Cartridge`.
- NES 2.0 *detection* (flagged on the header); only the iNES 1.0 subset of fields (bytes 4–7) is interpreted.
- Errors: not iNES (bad magic, or shorter than a header), truncated file (declared sizes exceed file length).
- `Ruby::Nes::Bits` with the two nibble helpers the header needs.
- A `local_rom:` spec metadata for the user's own dumps under `roms/` (skipped when absent, e.g. in CI).

Out: mapper behaviour (plan 04 onward), NES 2.0 extended fields (backlog), byte 8 PRG-RAM size (mappers decide;
plan 04), loading the trainer into `$7000` (no mapper needs it yet), VS/PlayChoice bits.

## Decisions

Settled with the user on 2026-11-17.

1. **Archaic headers: mask the mapper's high nibble.** When byte 7 bits 3-2 are `%01` (the detection procedure's
   "archaic iNES"), or when bytes 12–15 are not all zero and the header is not NES 2.0, the high nibble (byte 7) is
   ignored and the mapper number is byte 6's nibble alone. Reason: the iNES page's detection procedure ("If byte 7 AND
   $0C = $04, archaic iNES") and its rule of thumb ("if the last 4 bytes are not all zero, and the header is not
   marked for NES 2.0 format, an emulator should either mask off the upper 4 bits of the mapper number or simply refuse
   to load the ROM"); masking still loads old "DiskDude!" dumps (`'D'` = `$44` is itself marked archaic).
2. **ROM data as frozen `Array` of Integer.** `prg_rom`, `chr_rom` and `trainer` are frozen arrays of bytes, empty when
   absent (`chr_rom` is empty on CHR-RAM boards). The header gives `chr_ram?`, `chr_ram_size` (8 KiB on CHR-RAM boards,
   0 otherwise) and `trainer_size` (512 or 0); the mapper allocates the RAM. Reason: architecture decision 2 (memory is
   `Array` of Integer until plan 10); mappers index it directly. The 8 KiB is an emulator convention, not a header
   field: the iNES page only says size 0 "means the board uses CHR RAM", and the NES 2.0 page tells emulators not to
   assume 8 KiB for NES 2.0 headers — that is, it is what they assume for iNES 1.0.
3. **Byte 6 bit 3 is `alternative_nametables?`**, the raw bit with the NESdev name. Reason: its meaning is
   mapper-specific; calling it four-screen is the historical mistake the iNES page warns about.
4. **Local ROMs through a `local_rom:` metadata** (`spec/support/local_roms.rb`): `local_rom: 'smb3.nes'` (or a list)
   skips the group or example with a message when a dump under `roms/` is absent, and `local_rom_path` gives its path,
   refusing a name that was not declared. Tested with `TestRoms::SandboxedGroup`. Reason: plan 21 needs the same for
   SMB3.
5. **Trailing bytes are accepted silently.** Reason: the iNES page documents data after CHR-ROM (PlayChoice, titles).
6. **NES 2.0 is detected by the signature bits only** (`byte 7 AND $0C = $08`, as on the NES 2.0 page), without the
   iNES page's extra size check against byte 9. Reason: byte 9 is not interpreted, so the check could not be made
   meaningfully; NES 2.0 extended sizes are in the backlog. Known limits, accepted: a NES 2.0 image whose byte 9 is
   not zero (PRG ROM above 4 MiB or CHR ROM above 2 MiB, which no licensed game has) is cut with the iNES 1.0 sizes;
   ripper text whose byte 7 happens to read `%10` (`'H'` = `$48`) is taken as NES 2.0 and keeps byte 7's nibble.
7. **Errors live in `cartridge.rb`** (precedent: `Ruby::Nes::Error` in `nes.rb`): `Cartridge::Error <
   Ruby::Nes::Error`, `Cartridge::InvalidImage` (bad magic, or shorter than the header) and
   `Cartridge::TruncatedImage` (declared sizes exceed the file), each message naming the problem and the numbers. A
   missing or unreadable file is not wrapped: Ruby's `Errno` error already names the path.
8. **PRG ROM size 0 is not rejected here.** The iNES page does not define it; plan 04's `Mappers.build` refuses a
   cartridge without PRG ROM.
9. **Spec fixtures as hex dumps** (`spec/support/hex_dump.rb`): `HexDump.bytes('4E 45 53 1A …')` writes headers the
   way a hex editor shows them, and refuses anything that is not whole bytes of hex digits.

Review follow-ups (independent code review, accepted by the user on 2026-11-18): `chr_ram_size` is 0 on CHR-ROM
boards; byte 7 marked archaic masks the mapper (decision 1); `Header#trainer_size` replaces the loader's own constant;
`local_rom:` accepts lists and `local_rom_path` refuses undeclared names; `HexDump` refuses malformed dumps; "NES" and
"NES 2.0" added to the glossary; the "bytes 8 to 11" leaf now uses a non-zero mapper high nibble, so it would catch a
masking triggered by those bytes. Not applied: a shared installer for `local_rom:` and `test_rom:` (two users with
different checks), a builder for the loader's images and a shared temporary-directory context (each leaf spells its
own file layout; shared contexts are kept for shared production code).

## What was done

- `Ruby::Nes::Bits` with `high_nibble` and `combine_nibbles`; glossary anchors `high-nibble` and `combine-nibbles`,
  plus the terms NES and NES 2.0.
- `Ruby::Nes::Cartridge` (`Data.define(:header, :prg_rom, :chr_rom, :trainer)`) with `Error`, `InvalidImage` and
  `TruncatedImage`; `Cartridge::Header.parse` (magic, sizes, flags 6, NES 2.0 detection, mapper number with the archaic
  masking, `chr_ram_size`, `trainer_size`); `Cartridge::Loader.from_bytes`/`from_file` cutting trainer, PRG ROM and
  CHR ROM into frozen byte arrays.
- Spec support: `HexDump.bytes` for byte-literal fixtures and the `local_rom:` metadata (`LocalRoms`) for the user's
  own dumps; the SMB3 example passes locally and is skipped with a message where the dump is absent.
- Plans 04 and 11 updated with what the cartridge hands to the mappers and the meaning of byte 6 bit 3.
- 116 examples, full branch coverage of every new unit; one independent code review, follow-ups listed above.

## Tasks

- [x] `Ruby::Nes::Bits` (`lib/ruby/nes/bits.rb`) with `high_nibble` and `combine_nibbles`; glossary entries
      `high-nibble` and `combine-nibbles`.
- [x] Describe the header behaviour in prose → `specify-behavior` → `write-tests` (build headers from byte literals in
      specs, no ROM files needed); implement `Cartridge::Header`.
- [x] Same cycle for `Cartridge::Loader`; `Ruby::Nes::Cartridge` (`lib/ruby/nes/cartridge.rb`) with the errors,
      per the layout in `docs/architecture.md`.
- [x] `local_rom:` metadata in `spec/support/local_roms.rb`, installed in `spec/spec_helper.rb`.
- [x] One integration example (`local_rom: 'smb3.nes'`) that loads SMB3 and checks the values above.

## Acceptance criteria

- [x] Every header bit listed above is covered by a spec leaf (both mirroring values, battery, trainer and the offset
      it causes, alternative nametables, mapper nibble combination, archaic-header masking and its NES 2.0 exception,
      CHR-RAM case, NES 2.0 detection).
- [x] Bad magic and truncated files raise distinct, named errors with a message naming the problem.
- [x] Loading `roms/smb3.nes` yields mapper 4, PRG 262 144 bytes, CHR 131 072 bytes, horizontal mirroring, no
      battery; the example is skipped with a message when the file is absent.
- [x] 100% branch coverage on `Bits`, the header, the loader and `LocalRoms`; rubocop clean.
- [x] `bundle exec rake` green.

## References

- iNES — https://www.nesdev.org/wiki/INES
- NES 2.0 — https://www.nesdev.org/wiki/NES_2.0
- Mirroring — https://www.nesdev.org/wiki/Mirroring
- Mapper list — https://www.nesdev.org/wiki/Mapper
