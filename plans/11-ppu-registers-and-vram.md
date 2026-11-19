# 11 — PPU registers and VRAM

**Status:** done (2026-11-18)

**Depends on:** 04

## Goal

The CPU-visible side of the PPU and its memory: the eight registers at `$2000-$2007`, OAM DMA at `$4014`, the PPU bus
(pattern tables via the mapper, nametables with mirroring, palette RAM), and the internal scroll registers `v`, `t`,
`x`, `w`. No timing, no rendering yet.

## Context

Registers ([PPU registers](https://www.nesdev.org/wiki/PPU_registers)):

| Address | Name | Behaviour |
|---|---|---|
| `$2000` | PPUCTRL | `VPHB SINN`: nametable select (→ `t` bits 10–11), VRAM increment ("0: add 1, going across; 1: add 32, going down"), sprite and background pattern table, sprite size, master/slave, NMI enable |
| `$2001` | PPUMASK | `BGRs bMmG`: greyscale, left-8 clipping, show background/sprites, colour emphasis |
| `$2002` | PPUSTATUS | `VSOx xxxx`: VBlank (7), sprite 0 hit (6), sprite overflow (5), bits 4–0 "PPU open bus"; "Reading this register has the side effect of clearing the PPU's internal w register" |
| `$2003` | OAMADDR | |
| `$2004` | OAMDATA | "Writes will increment OAMADDR after the write; reads do not." |
| `$2005` | PPUSCROLL | two writes (X then Y) through `w`, "shared with PPUADDR" |
| `$2006` | PPUADDR | two writes, "high byte first"; "Bits 14 and 15 of the value written to this register are ignored"; second write copies `t` to `v` |
| `$2007` | PPUDATA | read through an internal buffer, except palette reads (below); "After access, the video memory address will increment by an amount determined by bit 2 of $2000." |
| `$4014` | OAMDMA | "256 pairs of a read from CPU memory and a write to OAMDATA"; "takes 513 or 514 cycles" |

Loopy registers ([PPU scrolling](https://www.nesdev.org/wiki/PPU_scrolling), "Register controls"): `v` and `t` are 15
bits ("Current VRAM address (15 bits)"), `x` is 3 bits, `w` is the write toggle.

```text
$2000 write         t: ...GH.. ........ <- d: ......GH
$2002 read          w:                  <- 0
$2005 first write   t: ....... ...ABCDE <- d: ABCDE...
                    x:              FGH <- d: .....FGH
                    w:                  <- 1
$2005 second write  t: FGH..AB CDE..... <- d: ABCDEFGH
                    w:                  <- 0
$2006 first write   t: .CDEFGH ........ <- d: ..CDEFGH
                    t: Z...... ........ <- 0 (bit Z is cleared)
                    w:                  <- 1
$2006 second write  t: ....... ABCDEFGH <- d: ABCDEFGH
                    v: <...all bits...> <- t: <...all bits...>
                    w:                  <- 0
```

"Outside of rendering, reads from or writes to $2007 will add either 1 or 32 to v"; "while the v register has 15 bits,
the PPU memory space is only 14 bits wide. The highest bit is unused for access through $2007."

PPUDATA palette reads (PPU registers, PPUDATA): "The referenced 6-bit palette data is returned immediately instead of
going to the internal read buffer"; "Simultaneously, the PPU also performs a normal read from PPU memory at the
specified address, "underneath" the palette data, and the result of this read goes into the read buffer as normal"
("usually mirrored nametables"); "The byte returned when reading palettes contains PPU open bus in the top 2 bits";
greyscale "clears the bottom 4 bits" (an AND with `$30`): "When reading from palette RAM, the returned value reflects
this AND behavior, but the underlying data is preserved."

PPU open bus ([Open bus behavior](https://www.nesdev.org/wiki/Open_bus_behavior#PPU_open_bus), PPU registers): the PPU
has an 8-bit I/O latch. "Writes to any PPU port, including the nominally read-only status port at $2002, load a value
onto the PPU's I/O bus"; "Reading a value from $2004 or $2007 loads a byte from OAM, video memory, or the palette onto
this bus"; "Reading the PPU's status port loads a value onto bits 7-5 of the bus, leaving the rest unchanged";
"Reading a nominally "write-only" register returns the latch's current value, as do the unused bits of PPUSTATUS."
"At least one bit in this value decays after 3ms to 30ms".

OAM ([PPU OAM](https://www.nesdev.org/wiki/PPU_OAM)): 64 sprites × 4 bytes. Byte 2's bits 2–4 are "Unimplemented (read
0)": "This can be emulated by ANDing byte 2 with $E3 either when writing to or when reading from OAM."

PPU memory map ([PPU memory map](https://www.nesdev.org/wiki/PPU_memory_map)): `$0000-$1FFF` pattern tables
(cartridge), `$2000-$2FFF` nametables (2 KiB internal VRAM through the mirroring mode), "$3000-3EFF is usually a mirror
of the 2kB region from $2000-2EFF", `$3F00-$3F1F` palette RAM, "$3F20-$3FFF ... Mirrors of $3F00-$3F1F".
[PPU palettes](https://www.nesdev.org/wiki/PPU_palettes): "Each byte in this palette RAM contains a 6-bit color value";
"entry 0 of each palette is also unique in that its color value is shared between the background and sprite palettes,
so writing to either one updates the same internal storage" — so `$3F10/$3F14/$3F18/$3F1C` share storage with
`$3F00/$3F04/$3F08/$3F0C`.

Mirroring ([Mirroring](https://www.nesdev.org/wiki/Mirroring), [PPU nametables](https://www.nesdev.org/wiki/PPU_nametables)).
The two pages name the arrangements in opposite ways; this project follows the Mirroring page, as the iNES header
(plan 03) already does:

| Mode | Logical `$2000/$2400/$2800/$2C00` → physical page | Wiring |
|---|---|---|
| `:horizontal` | 0, 0, 1, 1 | "connect PPU A11 to CIRAM A10" |
| `:vertical` | 0, 1, 0, 1 | "connect PPU A10 to CIRAM A10" |
| `:single_screen_lower` | 0, 0, 0, 0 | CIRAM A10 to ground ("screen A") |
| `:single_screen_upper` | 1, 1, 1, 1 | CIRAM A10 to Vcc ("the hidden screen B") |
| `:four_screen` | 0, 1, 2, 3 | "The cartridge contains additional VRAM used for all nametables" |

OAM DMA ([DMA](https://www.nesdev.org/wiki/DMA)): "OAM DMA halts the CPU, performs an optional alignment cycle, and then
gets and puts 256 times, taking 513 or 514 cycles." "DMA can only halt on CPU read cycles"; "If DMA tries to get on a
put cycle, it waits and tries again next cycle. This wait is called an alignment cycle." The page's examples: a `$4014`
write on a get cycle takes 513 cycles, one on a put cycle 514. "Get and put cycles are aligned to the first and second
halves of the APU clock"; "While these cycles are sometimes described as even and odd CPU cycles, this is not
accurate"; "At power-on, whether the first CPU cycle is get or put is random." The writes go through OAMDATA ("OAM DMA
copies 256 bytes from a CPU page to PPU OAM via the OAMDATA ($2004) register"), so they start at OAMADDR and, with
"Writes will increment OAMADDR", wrap around OAM.

Plan 04's `CpuBus` hands `$2000-$3FFF` to its `ppu_registers:` slot already mirrored down to `$2000-$2007`, as
`cpu_read(address, data_bus)` (return the value left on the CPU data bus) and `cpu_write(address, value)`. `$4014` is
inside the `io_registers:` slot's range (`$4000-$4017`).

## Scope

In: `Ppu` register reads/writes, `PpuBus`, nametable mirroring (horizontal, vertical, single-screen lower/upper,
four-screen; the mapper selects the mode — the iNES header's byte 6 bit 3 is an "alternative nametable layout" whose
meaning is mapper-specific, see plan 03), palette mirroring, loopy `v/t/x/w` updates on register writes, the PPU I/O
latch, OAM DMA with CPU stall cycles reported to `Cpu#step`.

Out: dot timing, VBlank and its clearing by a `$2002` read, NMI, register writes ignored after reset (plan 12);
rendering, the sprite 0 hit and overflow flags, OAMADDR reset during rendering, OAMDATA and PPUDATA accesses during
rendering (plans 13, 14); latch decay (Known gap).

## Decisions

Settled with the user on 2026-11-18.

1. **The PPU I/O latch is modelled without decay.** Every write to `$2000-$2007` loads it; reads of `$2004` and
   `$2007` load the byte read; a `$2002` read loads bits 7–5 only; write-only registers and `$2002`'s bits 4–0 answer
   it; palette reads take their top 2 bits from it. `Ppu#cpu_read` ignores the CPU's `data_bus`: the latch is the
   PPU's, not the CPU bus's. Reason: test ROMs and games read these bits; decay needs time (plan 12) and is a Known gap.
2. **OAM DMA belongs to the CPU bus: `CpuBus::OamDma`, created and owned by `CpuBus`, which routes `$4014` writes to it
   before the `io_registers:` slot.** Reason: the DMA's collaborators are the bus's own — reads in the CPU address
   space and writes to `$2004` through `ppu_registers` — so there is no circular wiring; the slot stays free for plans
   15 and 22 to decide on `$4016`/`$4017`. Reads of `$4014` keep going to the slot (open bus there).
3. **Stall channel and the get/put convention.** `CpuBus#take_stall_cycles(halt_cycle)` returns the stall cycles
   pending since the last call (0 almost always) and clears them; `Cpu#step` adds them to the instruction's cycles,
   passing the cycle the halt falls on (the cycles run so far). A CPU cycle is a **get cycle when its number in the
   CPU's count is even** (`Cpu.new` is cycle 0): a plain convention. The `$4014` write is the cycle before the halt, so
   the DMA takes 513 cycles when the write's cycle is even and 514 when it is odd. Mesen2's `NesCpu.cpp` lands on the
   same alignment with different arithmetic: it counts its reset as 8 cycles and, in its own numbering, its get cycles
   are the odd ones, while this project counts reset as 7 cycles (found by the plan's code review). Changing the reset
   cycle count flips the parity. Reason: the bus reports the stall and the CPU
   adds it (already in `docs/architecture.md`); the real alignment is random at power-on, so any fixed choice is a
   convention, recorded as a Known gap. The DMC (plan 23) reports through the same channel. `FlatBus` answers it too.
4. **VBlank, sprite 0 hit and overflow flags are left to plans 12 and 14.** Here `$2002` returns bits 7–5 as 0 with
   bits 4–0 from the latch, and clears `w`. Reason: the flags are set by timing and rendering; a setter only specs
   would call is not worth it. Plan 12 adds the "reading `$2002` clears VBlank" leaf.
5. **Four-screen is supported**: `PpuBus` holds 4 KiB of VRAM (the console's 2 KiB of CIRAM plus the 2 KiB a
   four-screen board brings). Reason: one table row; no board selects it yet.
6. **Mirroring is asked of the mapper on every nametable access** (`mapper.mirroring`), and a constant table maps the
   mode to the physical page of each logical nametable. The mapper interface's `mirroring` answers one of
   `:horizontal`, `:vertical`, `:single_screen_lower`, `:single_screen_upper`, `:four_screen`. Reason: MMC1, MMC3 and
   AxROM change it at runtime; plan 25 measures the lookup.
7. **OAM byte 2 is ANDed with `$E3` on write.** Reason: the PPU OAM page allows either; on write, the sprite renderer
   (plan 14) also sees the byte as the hardware holds it.
8. **The byte "underneath" a palette read is the nametable byte at `address - $1000`** (the `$2F00-$2FFF` mirror).
   Reason: the page says "a normal read from PPU memory at the specified address" and "usually mirrored nametables";
   `$3000-$3EFF` "is usually a mirror of" `$2000-$2EFF`, so `$3F00-$3FFF` reads the mirror of `$2F00-$2FFF`. An
   inference, documented as such.

## What was done

- `Ruby::Nes::PpuBus` decoding the 14-bit PPU space: pattern tables through the mapper, `PpuBus::Nametables` (4 KiB
  of VRAM, the five mirroring modes asked of the mapper on every access, the `$3000-$3EFF` mirror) and
  `PpuBus::PaletteRam` (32 entries of 6 bits, the shared entry 0 of each palette, the `$3F20-$3FFF` mirrors).
- `Ruby::Nes::Ppu` decoding `$2000-$2007` with the PPU's I/O latch (no decay), over `Ppu::ScrollRegisters` (v, t, x,
  w: each row of the "Register controls" table, the 15-bit increment), `Ppu::Oam` (OAMADDR, write with increment and
  wrap, byte 2 masked with `$E3`) and `Ppu::DataPort` (PPUDATA's read buffer, the palette exception with open bus
  and greyscale, the increment of 1 or 32).
- `CpuBus::OamDma`, owned by `CpuBus`, which routes `$4014` writes to it; `CpuBus#take_stall_cycles(halt_cycle)`
  reports 513 or 514 cycles (even CPU cycles are get cycles, a convention) and `Cpu#step` adds them; `FlatBus`
  answers the query.
- `docs/architecture.md`: PPU bus and mirroring table, PPU registers, the stall channel and the DMA unit, layout,
  decisions 20-22, five Known gaps rows; `docs/GLOSSARY.md`: get/put cycle, PPU I/O latch, v/t/x/w and the
  `low-bits`, `bit-field` and `place-bit-field` idioms. Plans 12, 14, 15, 19, 22, 23 and 25 aligned.
- 110 new examples, full branch coverage of every new unit; the stall query measured about −8% under YJIT on nestest,
  left to plan 25. One independent code review. Follow-ups applied: the broken Known gaps table, the get/put
  rationale (Mesen2 reaches the same alignment with 8 reset cycles and odd get cycles), the bench variants updated
  with the stall and the `$4014` route, an OAM DMA leaf with OAMADDR at `$F0` showing the wrap, `halt_cycle` named
  everywhere, the nametable stubs no longer tied to the number of calls, the PPUCTRL/PPUMASK leaves split by field
  (which also fixed a leaf that did not prove the PPUMASK write loads the latch), clearer names and reused
  constants. Not applied: a push model for the stall (plan 25), dropping the `$3F00` PPUDATA leaf (the comparison's
  boundary).

## Tasks

- [x] Specify and test `PpuBus::PaletteRam`: 6-bit entries, the shared entry 0 of each palette, `$3F20-$3FFF` mirrors.
- [x] Specify and test `PpuBus::Nametables`: each mirroring mode, the `$3000-$3EFF` mirror, a mode change at runtime.
- [x] Specify and test `PpuBus`: pattern tables through the mapper, nametables, palette.
- [x] Specify and test `Ppu::ScrollRegisters`: each row of the "Register controls" table, the `v` increment by 1 and 32.
- [x] Specify and test `Ppu::Oam`: address, write with increment and wrap, read without increment, byte 2 mask.
- [x] Specify and test the `$2007` port: non-palette buffered read, palette read, writes, increment by 1 and by 32.
- [x] Specify and test `Ppu`'s register decoding: each register, the latch, `$2002` clearing `w`.
- [x] Specify and test `CpuBus::OamDma`, the `$4014` route and `CpuBus#take_stall_cycles` (contents, OAMADDR wrap,
      513/514).
- [x] `Cpu#step` adds the bus's stall cycles; `FlatBus` answers `take_stall_cycles`.
- [x] `docs/architecture.md` (PPU bus, mapper `mirroring` values, stall channel, layout, decisions, known gaps) and
      `docs/GLOSSARY.md` (scroll registers, PPU I/O latch, get/put cycle, the `low-bits`, `bit-field` and
      `place-bit-field` idioms).
- [x] Measure the stall query once under YJIT and report the delta: nestest ran at 15.1 emulated MHz with the query
      and 16.4 without it (three alternating rounds of `ruby --yjit bench/cpu.rb`), about −8%; a pending flag in
      `CpuBus` did not help (the cost is the call per step).

## Acceptance criteria

- [x] `t`/`v`/`x`/`w` bit placement after each register write matches the "PPU scrolling" page's register summary.
- [x] Palette reads are unbuffered (top 2 bits from the latch, greyscale applied) and fill the buffer with the byte
      underneath; other `$2007` reads return the previous buffer; `v` advances by 1 or 32.
- [x] Each mirroring mode maps the four logical nametables to the documented physical ones; `$3000-$3EFF` mirrors
      `$2000-$2EFF`; sprite palettes' entry 0 shares storage with the background's; `$3F20-$3FFF` mirrors
      `$3F00-$3F1F`.
- [x] Write-only registers and `$2002`'s bits 4–0 return the latch; reading `$2002` clears `w`.
- [x] OAM DMA copies 256 bytes from `$XX00` starting at OAMADDR (wrapping), and `Cpu#step` reports 513 or 514 extra
      cycles following the get/put convention.
- [x] 100% branch coverage on the new units; rubocop clean; `bundle exec rake` green.

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
- PPU power up state — https://www.nesdev.org/wiki/PPU_power_up_state
- Mesen2 `Core/NES/NesCpu.cpp` (its get/put alignment, compared in decision 3) — https://github.com/SourMesen/Mesen2
