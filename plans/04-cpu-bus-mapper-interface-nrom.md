# 04 — CPU bus, mapper interface and NROM

**Status:** done (2026-11-18)

**Depends on:** 03

## Goal

A CPU bus that routes every address of the 64 KiB space to the right device, a mapper interface every cartridge board
implements, and the first mapper: NROM (mapper 0).

## Context

CPU memory map ([CPU memory map](https://www.nesdev.org/wiki/CPU_memory_map)):

| Range | Device |
|---|---|
| `$0000-$07FF` | 2 KiB internal RAM |
| `$0800-$1FFF` | mirrors of RAM (every `$0800`) |
| `$2000-$2007` | PPU registers |
| `$2008-$3FFF` | mirrors of PPU registers (every 8 bytes) |
| `$4000-$4017` | APU and I/O registers |
| `$4018-$401F` | "APU and I/O functionality that is normally disabled" |
| `$4020-$FFFF` | cartridge space (PRG-RAM usually at `$6000-$7FFF`, PRG-ROM at `$8000-$FFFF`) |

Open bus ([Open bus behavior](https://www.nesdev.org/wiki/Open_bus_behavior)): "reading open bus repeats the last value
that was read from the bus before this read", and "no circuit in the Control Deck decodes reads from $4000-$4014 or
$4018-$7FFF". The page describes reads only; it says nothing of writes leaving a value on the bus. Because instruction
fetches go through the bus too, "absolute addressed instructions will read the high byte of the address" follows from
tracking every read (plan 05 onward).

NROM ([NROM](https://www.nesdev.org/wiki/NROM)): "CPU $8000-$BFFF: First 16 KiB of PRG-ROM"; "CPU $C000-$FFFF: Last 16
KiB of PRG-ROM (NROM-256) or mirror of $8000-$BFFF (NROM-128)"; 8 KiB CHR-ROM; mapper 0 with 8 KiB CHR-RAM is
unlicensed/homebrew, and "most emulators will do the right thing" with it; mirroring fixed by solder pads (the iNES
header bit); no registers. PRG-RAM exists only on Family BASIC (2 or 4 KiB), and "most emulators will map 8KiB of
PRG-RAM to $6000-$7FFF if the battery flag is set (for iNES compatibility)".

From plan 03: `Cartridge` gives `prg_rom` and `chr_rom` as frozen `Array`s of Integer (`chr_rom` is empty on CHR-RAM
boards); the header gives `mapper_number`, `mirroring` (`:horizontal`/`:vertical`), `chr_ram?`, `chr_ram_size`
(8 KiB on CHR-RAM boards, 0 otherwise) and `alternative_nametables?` (byte 6 bit 3, raw: each mapper decides what it
means). The header does not interpret byte 8 (PRG-RAM size), so the PRG-RAM decision below is the mapper's. The
mapper allocates CHR-RAM itself. Plan 03 does not reject a header declaring no PRG ROM (byte 4 = 0): `Mappers.build`
refuses such a cartridge with a named error, before any mapper indexes an empty `prg_rom`.

## Scope

In:

- The mapper interface, documented in `lib/ruby/nes/mappers.rb` and `docs/architecture.md` (no base class yet):
  `cpu_read(address, data_bus)`, `cpu_write(address, value)`, `ppu_read(address)`, `ppu_write(address, value)`,
  `mirroring`, `irq?` (always false here).
- `Mappers.build(cartridge)` factory by mapper number; `Mappers::Error`, `Mappers::UnsupportedMapper` (names the
  number), `Mappers::InvalidCartridge` (no PRG ROM; NROM PRG ROM not 16 or 32 KiB).
- `Mappers::Nrom`.
- `Ruby::Nes::CpuBus` (`lib/ruby/nes/cpu_bus.rb`, top-level: the bus belongs to no device) with RAM, mirroring,
  open bus, and keyword slots `mapper:`, `ppu_registers:`, `io_registers:`, each defaulting to
  `CpuBus::Disconnected` (a null device answering open bus) until their plans exist.
- Glossary: I/O.

Out: PPU registers behaviour (plan 11), APU/controllers (plans 15, 22), a `Mappers::Base` (plan 19), an MMC3
scanline/A12 hook (plan 21), power-up contents of RAM (plan 07; zero for now).

## Decisions

Settled with the user on 2026-11-18.

1. **Devices receive the data bus and return what is left on it: `cpu_read(address, data_bus)`.** A device that does
   not drive the bus (NROM at `$5000`, a disconnected slot) returns `data_bus` unchanged; `CpuBus#read` stores every
   result as the new data bus value. Only CPU reads update it; writes do not. Reason: one Integer return type and no
   branch on the hot path (no `nil` sentinel); per-register partial open bus (plan 15's `$4016` bits 7-5 "repeat the
   corresponding bits from the previous read") becomes a device concern for free; the Open bus behavior page only
   documents reads. The data bus starts at 0 (plan 07 owns power-up state). Writes leaving the bus untouched is a
   project decision, not a documented fact (the 6502 does drive the data bus while writing): revisit with the open
   bus and `cpu_exec_space` test ROMs once the CPU runs (plans 08-12). Known limit: `$4015` is read inside the CPU
   and "the value does not affect open bus" ([APU](https://www.nesdev.org/wiki/APU)); this contract cannot say so,
   and plan 22 owns that decision.
2. **NROM always exposes 8 KiB of PRG-RAM at `$6000-$7FFF`**, battery flag or not. Reason: test ROMs write their
   results at `$6000`; the NROM page's "if the battery flag is set" describes what most emulators do, and a game
   depending on open bus there is not known. Revisit if a test ROM or game shows otherwise.
3. **No `Mappers::Base` and no scanline/A12 hook yet.** The interface is documented; plan 19 extracts a base class
   when a second mapper shows what is shared, and plan 21 decides the A12 hook's shape (it is an open decision there).
   Reason: no empty abstractions ahead of time (docs/architecture.md, Layout and loading).
4. **NROM refuses PRG ROM that is not 16 or 32 KiB** with `Mappers::InvalidCartridge` naming the size. Reason: the
   board only exists in those sizes, and the mirroring mask (`address & (size - 1)`) needs a power of two.
5. **NROM refuses CHR ROM that is not 8 KiB** (an empty CHR ROM is CHR RAM and is accepted), with
   `Mappers::InvalidCartridge` naming the size. Reason: the NROM page gives CHR capacity "8K"; consistent with
   decision 4. Settled while specifying NROM.
6. **`ppu_read`/`ppu_write` only take `$0000-$1FFF`**, a documented precondition with no check on the hot path: the
   only caller is the PPU bus (plan 11), which decodes pattern table addresses; anything else is a bug there.
7. **Spec cartridges are built in memory** by `Cartridges.build(prg_rom:, chr_rom:, mirroring:, mapper_number:)`
   (`spec/support/cartridges.rb`), the header sizes following the arrays. Reason: mapper and bus specs need many
   small synthetic cartridges; an iNES image per example would be noise. It defaults to the smallest valid NROM
   cartridge, copies the arrays before freezing them, and decides CHR RAM by an empty `chr_rom`, as `Nrom` does.
8. **NROM ignores the header's `alternative_nametables?`.** Reason: the NROM page gives only the solder-pad
   horizontal/vertical arrangement; plan 03 left the bit's meaning to each mapper.

## What was done

- `Ruby::Nes::Mappers` with the documented board interface, `Mappers.build` (table `{ 0 => Nrom }`) and the errors
  `Error`, `InvalidCartridge` (no PRG ROM; NROM sizes) and `UnsupportedMapper` (names the number).
- `Mappers::Nrom`: NROM-128 mirroring and NROM-256 through one power-of-two mask, 8 KiB of PRG RAM always present,
  open bus at `$4020-$5FFF`, CHR ROM read-only and CHR RAM writable, header mirroring, `irq?` false, refusal of PRG ROM
  other than 16/32 KiB and of CHR ROM other than 8 KiB.
- `Ruby::Nes::CpuBus` with 2 KiB of RAM and its mirrors, the PPU registers mirrored down to `$2000-$2007`, the APU and
  I/O slot, the disabled test range, the cartridge slot, and the data bus latch fed by every read;
  `CpuBus::Disconnected` as the empty slot.
- `docs/architecture.md`: devices on the CPU bus and the mapper interface; `docs/GLOSSARY.md`: I/O. Plans 11, 15, 19,
  21 and 22 aligned with the device contract, the deferred base class, the A12 hook, `$4015` and the shared
  `$4000-$4017` slot.
- Spec support: `Cartridges.build` for in-memory cartridges.
- 65 new examples, full branch coverage of every new unit; one independent code review. Review follow-ups applied:
  leaves for a PRG ROM write leaving PRG RAM alone and for a device's answer becoming open bus (both checked against
  the mutants the review found), the `$2008` write leaf, one source for CHR RAM in `Nrom`, builder defaults and copies,
  decision 8, the revisit note and `$4015` limit on decision 1, the I/O glossary wording. Not applied: reusing the
  header's size constants in `Nrom` (board sizes are a different concept).

## Tasks

- [x] Specify and test `Mappers::Nrom`: NROM-128 mirroring, NROM-256, PRG-RAM, open bus at `$4020-$5FFF`, writes to
      PRG ROM ignored, CHR-ROM read-only vs CHR-RAM writable, mirroring from the header, `irq?`, PRG size refusal.
- [x] Specify and test `Mappers.build`, including the unsupported-mapper and missing-PRG-ROM errors.
- [x] Specify and test `CpuBus::Disconnected`.
- [x] Specify and test `CpuBus` routing: each range, its mirrors and boundaries (`$07FF`/`$0800`, `$1FFF`/`$2000`,
      `$2007`/`$2008`, `$3FFF`/`$4000`, `$4017`/`$4018`, `$401F`/`$4020`), and open bus.
- [x] Document the mapper interface in `docs/architecture.md`; add I/O to `docs/GLOSSARY.md`.

## Acceptance criteria

- [x] Every boundary above is a spec leaf; RAM mirror writes are visible at all four mirrors.
- [x] An undriven read returns the last value read and leaves it unchanged.
- [x] NROM-128 reads the same byte at `$8000+n` and `$C000+n`; NROM-256 does not mirror.
- [x] Writes to CHR-ROM are ignored; writes to CHR-RAM persist; PRG-RAM reads back what was written.
- [x] Unsupported mapper raises an error naming the mapper number; a cartridge without PRG ROM raises a named error.
- [x] 100% branch coverage on bus, `Disconnected`, factory and NROM; rubocop clean.
- [x] `bundle exec rake` green.

## References

- CPU memory map — https://www.nesdev.org/wiki/CPU_memory_map
- Open bus behavior — https://www.nesdev.org/wiki/Open_bus_behavior
- APU (`$4015` and open bus) — https://www.nesdev.org/wiki/APU
- Mapper — https://www.nesdev.org/wiki/Mapper
- NROM — https://www.nesdev.org/wiki/NROM
