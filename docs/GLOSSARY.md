# Glossary

Three kinds of shorthand appear in ruby-nes code: hardware acronyms kept as names because the reference documentation
uses them, standard computing acronyms used by the tooling, and inline bit operations on hot paths. This page expands
all three. See
[`architecture.md`](architecture.md#readability) for when each is allowed.

A plan that introduces a new acronym or a new bit idiom adds it here in the same change. A `Bits` helper named under
[Bit operations](#bit-operations) is written by the first change whose code off the hot path needs it; until then
only the inline form exists.

## Hardware terms

| Term | Stands for | Meaning | Reference |
|---|---|---|---|
| 2A03 | Ricoh RP2A03 | The NTSC console's main chip: the CPU core and the APU together. | [CPU](https://www.nesdev.org/wiki/CPU) |
| 2C02 | Ricoh RP2C02 | The NTSC PPU chip. | [PPU palettes](https://www.nesdev.org/wiki/PPU_palettes) |
| A, X, Y, S, P, PC | Accumulator, index X, index Y, stack pointer, processor status, program counter | The 6502 registers: A, X, Y, S and P are byte-wide, PC has 16 bits. Code spells them out (`accumulator`, `index_x`, `index_y`, `Stack#pointer`, `Status`, `program_counter`); the letters stay in addressing mode names (`zero_page_x_address`) because NESdev names the modes after them. | [CPU registers](https://www.nesdev.org/wiki/CPU_registers) |
| APU | Audio Processing Unit | Programmable sound generator inside the 2A03, with 5 sound channels. | [APU](https://www.nesdev.org/wiki/APU) |
| Attribute table | — | 64 bytes at the end of each nametable choosing which palette each part of the background uses. | [PPU attribute tables](https://www.nesdev.org/wiki/PPU_attribute_tables) |
| BRK | Break | The 6502 software interrupt instruction; it uses the IRQ vector at `$FFFE` and pushes the B flag as 1. | [CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts) |
| CHR | Character (memory) | The pattern table data: tile shapes. On the cartridge, as CHR ROM or CHR RAM. | [PPU pattern tables](https://www.nesdev.org/wiki/PPU_pattern_tables) |
| CIRAM | — (NESdev uses the name without expanding it) | The console board's 2 KiB of VRAM, a separate SRAM chip holding two nametables. | [PPU nametables](https://www.nesdev.org/wiki/PPU_nametables) |
| CPU | Central Processing Unit | A 6502 core without decimal mode, inside the 2A03, at about 1.79 MHz (NTSC). | [CPU](https://www.nesdev.org/wiki/CPU) |
| DMA | Direct Memory Access | The 2A03's two copy units: OAM DMA (started by writing `$4014`) copies sprite data into OAM, and DMC DMA fetches sample bytes for the DMC. The CPU is halted while they run. | [DMA](https://www.nesdev.org/wiki/DMA) |
| DMC | Delta Modulation Channel | The APU channel that plays 1-bit delta-encoded samples. | [APU DMC](https://www.nesdev.org/wiki/APU_DMC) |
| Dot | — | One PPU clock; a scanline is 341 dots. | [PPU frame timing](https://www.nesdev.org/wiki/PPU_frame_timing) |
| I/O | Input/Output | The non-APU registers in `$4000-$4017`: OAM DMA (`$4014`) and the controller ports (`$4016`, `$4017`). `CpuBus`'s `io_registers:` slot receives the whole APU and I/O range, `$4000-$4017`. | [CPU memory map](https://www.nesdev.org/wiki/CPU_memory_map) |
| iNES | — | The `.nes` file format: a 16-byte header followed by PRG ROM and CHR ROM. | [iNES](https://www.nesdev.org/wiki/INES) |
| IRQ | Interrupt Request | Maskable, level-sensitive interrupt line (ignored while the I flag is set); vector at `$FFFE`. | [IRQ](https://www.nesdev.org/wiki/IRQ) |
| Mapper | — | The cartridge board's logic that maps PRG and CHR chips into the address spaces, often with bank switching. | [Mapper](https://www.nesdev.org/wiki/Mapper) |
| MMC3 | — (NESdev uses the name without expanding "MMC") | Nintendo's mapper chip with a scanline IRQ; iNES mapper 4. Used by Super Mario Bros. 3. | [MMC3](https://www.nesdev.org/wiki/MMC3) |
| Nametable | — | 1024-byte background layout: 960 tile indices plus a 64-byte attribute table. | [PPU nametables](https://www.nesdev.org/wiki/PPU_nametables) |
| NES | Nintendo Entertainment System | The console this project emulates (NTSC model). Also the first three bytes of the iNES magic, `"NES"` + `$1A`. | [NES reference guide](https://www.nesdev.org/wiki/NES_reference_guide) |
| NES 2.0 | — | The extended successor of the iNES header, recognised by byte 7 bits 3-2 = `%10`; only detected here (`Header#nes2?`), its extended fields are not read. | [NES 2.0](https://www.nesdev.org/wiki/NES_2.0) |
| NMI | Non-Maskable Interrupt | Interrupt the program cannot mask with the I flag. The PPU raises it at the start of VBlank when NMI generation is enabled in PPUCTRL. Vector at `$FFFA`. | [NMI](https://www.nesdev.org/wiki/NMI) |
| NTSC | National Television System Committee | The video standard of North American and Japanese consoles; the timing this project emulates. | [Cycle reference chart](https://www.nesdev.org/wiki/Cycle_reference_chart) |
| OAM | Object Attribute Memory | PPU-internal memory with the sprite display list: 64 sprites × 4 bytes. | [PPU OAM](https://www.nesdev.org/wiki/PPU_OAM) |
| Open bus | — | Reading an address no device answers; the result is usually the last value on the data bus. | [Open bus behavior](https://www.nesdev.org/wiki/Open_bus_behavior) |
| PAL | Phase Alternating Line | The European video standard, with different clock ratios and frame timing; not emulated (backlog). | [Cycle reference chart](https://www.nesdev.org/wiki/Cycle_reference_chart) |
| Palette | — | 6-bit colour indices (one of 64 colours); 4 background and 4 sprite palettes at `$3F00-$3F1F`. | [PPU palettes](https://www.nesdev.org/wiki/PPU_palettes) |
| Pattern table | — | PPU memory defining tile shapes (the CHR data). | [PPU pattern tables](https://www.nesdev.org/wiki/PPU_pattern_tables) |
| PPU | Picture Processing Unit | Generates the video signal, 240 lines of pixels. | [PPU](https://www.nesdev.org/wiki/PPU) |
| PPUCTRL … PPUDATA | PPU registers | `$2000` PPUCTRL, `$2001` PPUMASK, `$2002` PPUSTATUS, `$2003` OAMADDR, `$2004` OAMDATA, `$2005` PPUSCROLL, `$2006` PPUADDR, `$2007` PPUDATA; `$4014` OAMDMA. | [PPU registers](https://www.nesdev.org/wiki/PPU_registers) |
| PRG | Program (memory) | The cartridge memory on the CPU side: PRG ROM (16 KiB units in iNES) with the program, and PRG RAM (also called WRAM), usually at `$6000-$7FFF`. | [iNES](https://www.nesdev.org/wiki/INES), [CPU memory map](https://www.nesdev.org/wiki/CPU_memory_map) |
| RAM | Random-Access Memory | Readable and writable memory: the console's 2 KiB internal RAM at `$0000-$07FF`, and on some cartridges PRG RAM and CHR RAM. | [CPU memory map](https://www.nesdev.org/wiki/CPU_memory_map) |
| ROM | Read-Only Memory | The cartridge's PRG ROM and CHR ROM. By extension, a dumped cartridge image (an iNES file), as in "test ROM". | [iNES](https://www.nesdev.org/wiki/INES) |
| Scanline | — | One row of the frame; 262 per NTSC frame. | [PPU rendering](https://www.nesdev.org/wiki/PPU_rendering) |
| Sprite 0 hit | — | A PPUSTATUS flag set when sprite 0 overlaps the background; games poll it to time mid-frame effects such as a fixed status bar. | [PPU registers](https://www.nesdev.org/wiki/PPU_registers) |
| Status flags | — | The CPU's P register, bits `NV1B DIZC`: N negative, V overflow, B break (not a real flag), D decimal, I interrupt disable, Z zero, C carry. | [Status flags](https://www.nesdev.org/wiki/Status_flags) |
| VBlank | Vertical blanking | Scanlines 241–260, when the PPU makes no memory accesses; the VBlank flag is set at scanline 241, dot 1. | [PPU rendering](https://www.nesdev.org/wiki/PPU_rendering) |
| VRAM | Video RAM | The PPU's nametable memory; on the console, the 2 KiB CIRAM. | [PPU nametables](https://www.nesdev.org/wiki/PPU_nametables) |

## Computing terms

Standard acronyms used by the tooling around the emulator (the test ROM harness, for now), kept in names because they
are what the libraries and protocols call them.

| Term | Stands for | Meaning | Reference |
|---|---|---|---|
| HTTP | Hypertext Transfer Protocol | The protocol the test ROM downloader speaks; a `200` status is a delivered file. | [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) |
| SHA-256 | Secure Hash Algorithm, 256-bit | The digest the test ROM manifest records for each file; a matching digest means the bytes are the expected ones. | [FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final) |
| SSL | Secure Sockets Layer | Name kept by Ruby `Net::HTTP` (`use_ssl:`) for an encrypted (TLS) connection. | [Net::HTTP](https://docs.ruby-lang.org/en/master/Net/HTTP.html) |
| URL | Uniform Resource Locator | The address of a file on the web, e.g. a test ROM at one of the manifest sources. | [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) |
| YAML | YAML Ain't Markup Language | The format of the test ROM manifest (`spec/fixtures/test_roms.yml`). | [YAML](https://yaml.org/) |

## Bit operations

Each entry is the anchor cited by a `# glossary: <term>` tag on a hot-path line, and names the `Ruby::Nes::Bits`
helper that code off the hot path calls instead. Constants are shown with their values; the code always uses the
constant name.

- A tag names the **intent**, not the expression: `low-byte` and `wrap-to-byte` are both `& BYTE_MASK`.
- Inside these idioms the byte width `8` and the single bit `1` are not magic numbers.
- **Flag tests are not inline idioms.** Test bits with `anybits?`, `allbits?` or `nobits?` everywhere, hot paths
  included (`status.anybits?(CARRY_FLAG)`, `value.anybits?(SIGN_BIT)` for the sign bit). RuboCop's
  `Style/BitwisePredicate` rejects `register & FLAG != 0`.

### wrap-to-byte

- Inline: `value & BYTE_MASK` (`BYTE_MASK = 0xFF`)
- Off the hot path: `Bits.wrap_to_byte(value)`
- Keeps the low 8 bits, so `0x100` becomes `0x00` and `0x1FF` becomes `0xFF`: an 8-bit register overflowing.

### wrap-to-word

- Inline: `value & WORD_MASK` (`WORD_MASK = 0xFFFF`)
- Off the hot path: `Bits.wrap_to_word(value)`
- Keeps the low 16 bits: a 16-bit address or program counter wrapping past `$FFFF` to `$0000`.

### low-byte

- Inline: `word & BYTE_MASK`
- Off the hot path: `Bits.low_byte(word)`
- The low 8 bits of a 16-bit value (`$12AB` → `$AB`). Same expression as wrap-to-byte; the intent is taking the low
  half of an address rather than wrapping an overflow.

### high-byte

- Inline: `word >> 8`
- Off the hot path: `Bits.high_byte(word)`
- The high 8 bits of a 16-bit value (`$12AB` → `$12`). Assumes the value already fits in 16 bits.

### combine-bytes

- Inline: `(high << 8) | low`
- Off the hot path: `Bits.combine_bytes(low: 0xAB, high: 0x12)` → `0x12AB`
- Builds a 16-bit value from its two halves. Keyword arguments keep the order of the halves explicit.

### high-nibble

- Inline: `(byte >> NIBBLE_WIDTH) & NIBBLE_MASK` (`NIBBLE_WIDTH = 4`, `NIBBLE_MASK = 0x0F`)
- Off the hot path: `Bits.high_nibble(byte)`
- The upper 4 bits of a byte as a number `0-15` (`$4A` → `$4`); the low 4 bits never influence it. The iNES header
  keeps the mapper number's halves in the high nibbles of bytes 6 and 7 ([iNES](https://www.nesdev.org/wiki/INES)).

### combine-nibbles

- Inline: `(high << NIBBLE_WIDTH) | low`
- Off the hot path: `Bits.combine_nibbles(low: 0x1, high: 0x2)` → `0x21`
- Builds a byte from its two 4-bit halves. Keyword arguments keep the order of the halves explicit.

### set-flag

- Inline: `register | FLAG`
- Off the hot path: `Bits.set_flag(register, FLAG)`
- Turns the flag's bit on, leaving the others untouched.

### clear-flag

- Inline: `register & ~FLAG`
- Off the hot path: `Bits.clear_flag(register, FLAG)`
- Turns the flag's bit off, leaving the others untouched. (`~FLAG` is negative in Ruby, but and-ing it with a
  non-negative register keeps the result non-negative and within the register's width.)

### toggle-flag

- Inline: `register ^ FLAG`
- Off the hot path: `Bits.toggle_flag(register, FLAG)`
- Flips the flag's bit.

### bit-at

- Inline: `(value >> index) & 1`
- Off the hot path: `Bits.bit_at(value, index)`
- The bit at position `index` (0 is the lowest) as `0` or `1`, for copying a bit into another value (a shifted-out
  bit into the carry, for example). To *test* a bit, use `anybits?`.

### signed-byte

- Inline: `value >= SIGN_BIT ? value - BYTE_RANGE : value` (`SIGN_BIT = 0x80`, `BYTE_RANGE = 0x100`)
- Off the hot path: `Bits.to_signed_byte(value)`
- Reads a byte as two's complement, `-128..127` (`$FE` → `-2`). Used for relative branch offsets.

### shift-left

- Inline: `value << 1`
- Off the hot path: the same expression; the operator is already the clearest form, so there is no helper.
- Moves every bit one position up (doubles the value). Bit 7 leaves the byte; wrap afterwards.

### shift-right

- Inline: `value >> 1`
- Off the hot path: the same expression; no helper.
- Moves every bit one position down (halves the value, rounding down). Bit 0 is dropped.

### mirror-down

- Inline: `address & MIRROR_MASK` (for example `RAM_MIRROR_MASK = 0x07FF`)
- Off the hot path: `Bits.mirror_down(address, MIRROR_MASK)`
- Folds a mirrored range onto its base copy: `$0800`, `$1000` and `$1800` all reach RAM address `$0000`
  ([CPU memory map](https://www.nesdev.org/wiki/CPU_memory_map)).

### increment-within-page

- Inline: `(address & PAGE_MASK) | ((address + 1) & BYTE_MASK)`
- Off the hot path: `Bits.increment_within_page(address)`
- The next address without carrying into the next page: `$10FF` → `$1000`, not `$1100`. Indirect `JMP` reads its
  pointer's high byte this way: "JMP ($03FF) reads $03FF and $0300 instead of $0400"
  ([Instruction reference](https://www.nesdev.org/wiki/Instruction_reference)). In page zero it is plain wrap-to-byte.

### page-crossed

- Inline: `(first & PAGE_MASK) != (second & PAGE_MASK)` (`PAGE_MASK = 0xFF00`)
- Off the hot path: `Bits.page_crossed?(first, second)`
- True when two addresses fall in different 256-byte pages. Indexed reads that cross a page cost the CPU one extra
  cycle ([CPU addressing modes](https://www.nesdev.org/wiki/CPU_addressing_modes)).
