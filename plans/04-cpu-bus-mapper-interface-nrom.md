# 04 — CPU bus, mapper interface and NROM

**Depends on:** 03

## Goal

A CPU bus that routes every address of the 64 KiB space to the right device, a mapper interface every cartridge board
implements, and the first mapper: NROM (mapper 0).

## Context

CPU memory map:

| Range | Device |
|---|---|
| `$0000-$07FF` | 2 KiB internal RAM |
| `$0800-$1FFF` | mirrors of RAM (every `$0800`) |
| `$2000-$2007` | PPU registers |
| `$2008-$3FFF` | mirrors of PPU registers (every 8 bytes) |
| `$4000-$4017` | APU and I/O registers |
| `$4018-$401F` | normally disabled test functionality |
| `$4020-$FFFF` | cartridge space (PRG-RAM usually at `$6000-$7FFF`, PRG-ROM at `$8000-$FFFF`) |

Reads from unmapped addresses return the last value on the data bus (open bus).

NROM: PRG-ROM of 16 KiB (mirrored at `$8000` and `$C000`) or 32 KiB; 8 KiB CHR-ROM (or CHR-RAM); fixed mirroring
from the header. Real NROM boards rarely have PRG-RAM, but emulators expose 8 KiB at `$6000-$7FFF` because test ROMs
(blargg) write their results there.

## Scope

In:

- `Mappers::Base` interface: `cpu_read(address)`, `cpu_write(address, value)`, `ppu_read(address)`,
  `ppu_write(address, value)`, `mirroring`, `irq?` (always false here), plus a scanline/A12 hook reserved for MMC3
  (no-op default).
- `Mappers.build(cartridge)` factory by mapper number; unknown mapper → named error.
- `Mappers::Nrom`.
- `CpuBus` with RAM, mirroring, open bus, and slots for PPU/APU/IO devices (stubs answering open bus until their
  plans exist).

Out: PPU registers behaviour (plan 11), APU/controllers (plans 15, 22).

## Open decisions

- Open bus scope: track only the CPU data bus last value (simple) or also per-register partial open bus (`$4015`,
  controller upper bits)? Recommendation: CPU data bus only now; refine in the plans of those registers.
- PRG-RAM on NROM: always 8 KiB (recommended, matches test ROMs), or only when the header says so.

## Tasks

- [ ] Specify and test `CpuBus` routing: each range, its mirrors and boundaries (`$07FF`/`$0800`, `$1FFF`/`$2000`,
      `$3FFF`/`$4000`, `$401F`/`$4020`).
- [ ] Specify and test NROM for 16 KiB and 32 KiB PRG, CHR-ROM read-only vs CHR-RAM writable, PRG-RAM.
- [ ] Specify and test the factory, including the unknown-mapper error.

## Acceptance criteria

- [ ] Every boundary above is a spec leaf; RAM mirror writes are visible at all four mirrors.
- [ ] NROM-128 reads the same byte at `$8000+n` and `$C000+n`; NROM-256 does not mirror.
- [ ] Writes to CHR-ROM are ignored; writes to CHR-RAM persist.
- [ ] Unknown mapper raises an error naming the mapper number.
- [ ] 100% branch coverage on bus and NROM; rubocop clean.

## References

- CPU memory map — https://www.nesdev.org/wiki/CPU_memory_map
- Open bus behavior — https://www.nesdev.org/wiki/Open_bus_behavior
- Mapper — https://www.nesdev.org/wiki/Mapper
- NROM — https://www.nesdev.org/wiki/NROM
