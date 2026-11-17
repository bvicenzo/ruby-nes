# 11 — PPU registers and VRAM

**Depends on:** 04

## Goal

The CPU-visible side of the PPU and its memory: the eight registers at `$2000-$2007`, OAM DMA at `$4014`, the PPU bus
(pattern tables via the mapper, nametables with mirroring, palette RAM), and the internal scroll registers `v`, `t`,
`x`, `w`. No timing, no rendering yet.

## Context

Registers:

| Address | Name | Behaviour |
|---|---|---|
| `$2000` | PPUCTRL | nametable select (→ `t` bits 10–11), VRAM increment (1/32), sprite and background pattern table, sprite size, NMI enable |
| `$2001` | PPUMASK | greyscale, left-8 clipping, show background/sprites, colour emphasis |
| `$2002` | PPUSTATUS | VBlank (bit 7), sprite 0 hit (6), sprite overflow (5); reading clears VBlank and `w` |
| `$2003` | OAMADDR | |
| `$2004` | OAMDATA | write increments OAMADDR |
| `$2005` | PPUSCROLL | two writes (X then Y) through `w` |
| `$2006` | PPUADDR | two writes (high then low) through `w`; second write copies `t` to `v` |
| `$2007` | PPUDATA | read buffered (one read behind) except palette, which returns directly while the buffer is filled from the nametable "below" it; increments `v` |
| `$4014` | OAMDMA | copies 256 bytes from `$XX00` to OAM; stalls the CPU 513 or 514 cycles |

PPU memory map: `$0000-$1FFF` pattern tables (cartridge), `$2000-$2FFF` nametables (2 KiB internal VRAM through the
mirroring mode), `$3000-$3EFF` mirror of `$2000-$2EFF`, `$3F00-$3F1F` palette RAM mirrored up to `$3FFF`, with
`$3F10/$3F14/$3F18/$3F1C` mirroring `$3F00/$3F04/$3F08/$3F0C`.

## Scope

In: `Ppu` register reads/writes, `PpuBus`, nametable mirroring (horizontal, vertical, single-screen lower/upper,
four-screen), palette mirroring, loopy `v/t/x/w` updates on register writes, OAM DMA with CPU stall cycles reported to
the console.

Out: dot timing, VBlank, NMI (plan 12); rendering (plans 13, 14).

## Open decisions

- PPU open bus (the I/O latch returned in unused bits and write-only registers, with decay): model the latch without
  decay (recommended) or skip it?
- Who executes the DMA stall: the CPU (adds cycles to the current step) or the console. Recommendation: the CPU bus
  reports stall cycles; `Cpu#step` adds them (keeps the console loop simple).

## Tasks

- [ ] Specify and test each register, with leaves for the first/second write of `$2005`/`$2006` and the `w` reset by
      reading `$2002`.
- [ ] Specify and test the `$2007` read buffer: non-palette, palette, increment by 1 and by 32.
- [ ] Specify and test nametable mirroring for every mode and palette mirroring for the four aliased entries.
- [ ] Specify and test OAM DMA (contents and 513/514 stall depending on CPU cycle parity).

## Acceptance criteria

- [ ] `t`/`v`/`x`/`w` bit placement after each register write matches the "PPU scrolling" page's register summary.
- [ ] Palette reads are unbuffered; other `$2007` reads return the previous buffer.
- [ ] Each mirroring mode maps the four logical nametables to the documented physical ones.
- [ ] OAM DMA copies 256 bytes starting at OAMADDR (wrapping) and stalls the documented cycles.
- [ ] 100% branch coverage; rubocop clean.

## References

- PPU registers — https://www.nesdev.org/wiki/PPU_registers
- PPU memory map — https://www.nesdev.org/wiki/PPU_memory_map
- PPU scrolling (loopy registers) — https://www.nesdev.org/wiki/PPU_scrolling
- PPU nametables — https://www.nesdev.org/wiki/PPU_nametables
- PPU palettes — https://www.nesdev.org/wiki/PPU_palettes
- Mirroring — https://www.nesdev.org/wiki/Mirroring
- PPU OAM — https://www.nesdev.org/wiki/PPU_OAM
- DMA — https://www.nesdev.org/wiki/DMA
- Open bus behavior (PPU) — https://www.nesdev.org/wiki/Open_bus_behavior#PPU_open_bus
