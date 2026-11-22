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
| A12 (PPU) | Address line 12 | Bit 12 (`$1000`) of the PPU's address bus: high for pattern table 1. MMC3 clocks its IRQ counter on its filtered rising edges, which pattern fetches, PPUDATA accesses and PPUADDR writes cause; `Mappers::Mmc3::A12Watcher`. | [MMC3](https://www.nesdev.org/wiki/MMC3#IRQ_Specifics) |
| APU | Audio Processing Unit | Programmable sound generator inside the 2A03, with 5 sound channels. | [APU](https://www.nesdev.org/wiki/APU) |
| APU cycle | — | Two CPU cycles: the frame counter's sequencer "is clocked on every other CPU cycle", and the pulse, noise and DMC timers too. Its halves are the get and put cycles. | [APU Frame Counter](https://www.nesdev.org/wiki/APU_Frame_Counter) |
| Attribute table | — | 64 bytes at the end of each nametable choosing which palette each part of the background uses. | [PPU attribute tables](https://www.nesdev.org/wiki/PPU_attribute_tables) |
| AxROM | — (Nintendo's board names, AMROM, ANROM, AN1ROM and AOROM) | iNES mapper 7: one switchable 32 KiB PRG ROM bank, 8 KiB of CHR RAM, and a single-screen nametable the program picks; `Mappers::Axrom`. | [AxROM](https://www.nesdev.org/wiki/AxROM) |
| Bank | — | A fixed-size slice of PRG ROM or CHR that a board can show in an address window; bank switching is choosing which one. `Mappers::Base` keeps one offset per window. | [Mapper](https://www.nesdev.org/wiki/Mapper) |
| BRK | Break | The 6502 software interrupt instruction; it uses the IRQ vector at `$FFFE` and pushes the B flag as 1. | [CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts) |
| Bus conflict | — | A write to a register that overlaps ROM while the ROM still drives the data bus: "an emulator should use the bitwise AND of the value from the CPU and the value from the ROM". Emulated on CNROM only (architecture decision 47). | [Bus conflict](https://www.nesdev.org/wiki/Bus_conflict) |
| CHR | Character (memory) | The pattern table data: tile shapes. On the cartridge, as CHR ROM or CHR RAM. | [PPU pattern tables](https://www.nesdev.org/wiki/PPU_pattern_tables) |
| CIRAM | — (NESdev uses the name without expanding it) | The console board's 2 KiB of VRAM, a separate SRAM chip holding two nametables. | [PPU nametables](https://www.nesdev.org/wiki/PPU_nametables) |
| CNROM | — (Nintendo's board name) | iNES mapper 3: 16 or 32 KiB of fixed PRG ROM and one switchable 8 KiB CHR ROM bank, with bus conflicts; `Mappers::Cnrom`. | [CNROM](https://www.nesdev.org/wiki/CNROM) |
| CPU | Central Processing Unit | A 6502 core without decimal mode, inside the 2A03, at about 1.79 MHz (NTSC). | [CPU](https://www.nesdev.org/wiki/CPU) |
| DMA | Direct Memory Access | The 2A03's two copy units: OAM DMA (started by writing `$4014`) copies sprite data into OAM, and DMC DMA fetches sample bytes for the DMC. The CPU is halted while they run. | [DMA](https://www.nesdev.org/wiki/DMA) |
| DMC | Delta Modulation Channel | The APU channel that plays 1-bit delta-encoded samples read from CPU memory: each bit moves a 7-bit level up or down by 2 (`Apu::Dmc`). Its fetches are DMC DMA: a load after a `$4015` write, a reload when the sample buffer empties. | [APU DMC](https://www.nesdev.org/wiki/APU_DMC) |
| Dot | — | One PPU clock; a scanline is 341 dots. | [PPU frame timing](https://www.nesdev.org/wiki/PPU_frame_timing) |
| Dummy read | — | A read the 6502 makes and throws away. The indexed modes read the address whose high byte is not fixed yet, "smaller by $100" on a page cross; writes and read-modify-write instructions always do it. It matters when the address is a register with read side effects (`$2002`, `$2007`). | [6502_cpu.txt](https://www.nesdev.org/6502_cpu.txt) |
| Duty cycle | — | The fraction of a pulse wave spent high: 12.5%, 25%, 50% or 25% negated, picked by bits 7-6 of `$4000`/`$4004`; `Apu::DutySequencer`. | [APU Pulse](https://www.nesdev.org/wiki/APU_Pulse) |
| Envelope | — | The unit giving a channel its volume: a constant one, or a decay from 15 to 0 that may loop, clocked by quarter frames; `Apu::Envelope`. | [APU Envelope](https://www.nesdev.org/wiki/APU_Envelope) |
| Frame counter | — | The APU's sequencer (`$4017`): 4-step or 5-step, it clocks quarter and half frames at fixed cycles and, in 4-step mode, sets the frame interrupt flag (the IRQ source `FRAME_IRQ`); `Apu::FrameCounter`, `Apu::InterruptFlag`. Not related to the PPU's frames. | [APU Frame Counter](https://www.nesdev.org/wiki/APU_Frame_Counter) |
| Get/put cycle | — | The two halves of each APU cycle; a DMA reads (gets) on the first and writes (puts) on the second. OAM DMA takes 513 cycles when `$4014` is written on a get cycle and 514 on a put cycle; the emulator takes even CPU cycles as get cycles, by convention, and calibrates the APU's `$4017` delay against it (plan 22). | [DMA](https://www.nesdev.org/wiki/DMA) |
| I/O | Input/Output | The non-APU registers in `$4000-$4017`: OAM DMA (`$4014`) and the controller ports (`$4016`, `$4017`). `CpuBus` routes the controller ports to its `controller_ports:` slot and the rest of `$4000-$4017` to `apu_registers:` (plan 15). | [CPU memory map](https://www.nesdev.org/wiki/CPU_memory_map) |
| I/O latch (PPU) | — | The PPU's own open bus: an 8-bit latch that every write to `$2000-$2007` loads; write-only registers and PPUSTATUS's bits 4-0 read it back. Not the CPU's data bus. | [Open bus behavior](https://www.nesdev.org/wiki/Open_bus_behavior#PPU_open_bus) |
| iNES | — | The `.nes` file format: a 16-byte header followed by PRG ROM and CHR ROM. | [iNES](https://www.nesdev.org/wiki/INES) |
| Interrupt hijacking | — | An NMI asserted during the first four ticks of BRK or of an IRQ sequence makes it load the NMI vector instead ("an NMI can hijack an IRQ"). | [CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts#Interrupt_hijacking) |
| IRQ | Interrupt Request | Maskable, level-sensitive interrupt line (ignored while the I flag is set); vector at `$FFFE`. | [IRQ](https://www.nesdev.org/wiki/IRQ) |
| JAM | — (6502_cpu.txt: "Jams the machine"; the wiki's matrix calls it STP) | The 12 unofficial opcodes (`$02`, `$12`, … `$F2`) that "halt the CPU until reset"; `Cpu#jammed?` reports it. | [CPU unofficial opcodes](https://www.nesdev.org/wiki/CPU_unofficial_opcodes) |
| Length counter | — | A channel's countdown, loaded from a 32-entry table and clocked by half frames, that silences the channel at 0; `$4015` reports which are above 0. `Apu::LengthCounter`. | [APU Length Counter](https://www.nesdev.org/wiki/APU_Length_Counter) |
| LFSR | Linear Feedback Shift Register | A shift register whose input bit is computed from its own bits; the noise channel's 15-bit one (`Apu::NoiseShiftRegister`) feeds bit 0 exclusive-ored with bit 1, or bit 6 in periodic mode, into bit 14. | [APU Noise](https://www.nesdev.org/wiki/APU_Noise) |
| Linear counter | — | The triangle's second gate, clocked by quarter frames: reloaded while its reload flag is set, counting down otherwise; the triangle steps only while it and the length counter are above 0 (`Apu::LinearCounter`). | [APU Triangle](https://www.nesdev.org/wiki/APU_Triangle) |
| M2 | — (the 2A03's clock output pin) | The CPU clock as the cartridge sees it, one cycle per CPU cycle; MMC3's A12 filter counts its falling edges ("three falling edges of M2"), modelled as the PPU's elapsed dots divided by 3. | [MMC3](https://www.nesdev.org/wiki/MMC3#IRQ_Specifics) |
| Magic constant | — | The chip- and temperature-dependent byte that the unstable ANE (`$8B`) and LAX #imm (`$AB`) OR into A; the emulator uses $EF for ANE, as "No More Secrets" advises for emulators, and $FF for LAX #imm, the value blargg's `instr_test-v5` needs. | ["No More Secrets"](https://csdb.dk/release/?id=198357) |
| Mapper | — | The cartridge board's logic that maps PRG and CHR chips into the address spaces, often with bank switching. | [Mapper](https://www.nesdev.org/wiki/Mapper) |
| Mixer | — | The APU's two non-linear digital-to-analog converters (pulses; triangle, noise and DMC) adding up to an output of 0.0-1.0, computed here through the page's lookup tables (`Apu::Mixer`). | [APU Mixer](https://www.nesdev.org/wiki/APU_Mixer) |
| MMC1 | — (NESdev uses the name without expanding "MMC") | Nintendo's mapper chip with a 5-bit serial port and four registers (Control, CHR bank 0, CHR bank 1, PRG bank): 16 or 32 KiB PRG banking, 4 or 8 KiB CHR banking, runtime mirroring; iNES mapper 1, the MMC1B revision. `Mappers::Mmc1`. | [MMC1](https://www.nesdev.org/wiki/MMC1) |
| MMC3 | — (NESdev uses the name without expanding "MMC") | Nintendo's mapper chip with a scanline IRQ; iNES mapper 4: 8 KiB PRG and 1 or 2 KiB CHR banks through eight bank registers, runtime mirroring, and an IRQ counter clocked by rising edges of PPU A12. Used by Super Mario Bros. 3. `Mappers::Mmc3`. | [MMC3](https://www.nesdev.org/wiki/MMC3) |
| Nametable | — | 1024-byte background layout: 960 tile indices plus a 64-byte attribute table. | [PPU nametables](https://www.nesdev.org/wiki/PPU_nametables) |
| NES | Nintendo Entertainment System | The console this project emulates (NTSC model). Also the first three bytes of the iNES magic, `"NES"` + `$1A`. | [NES reference guide](https://www.nesdev.org/wiki/NES_reference_guide) |
| NES 2.0 | — | The extended successor of the iNES header, recognised by byte 7 bits 3-2 = `%10`; only detected here (`Header#nes2?`), its extended fields are not read. | [NES 2.0](https://www.nesdev.org/wiki/NES_2.0) |
| NMI | Non-Maskable Interrupt | Interrupt the program cannot mask with the I flag. The PPU raises it at the start of VBlank when NMI generation is enabled in PPUCTRL. Vector at `$FFFA`. | [NMI](https://www.nesdev.org/wiki/NMI) |
| NROM | — (Nintendo's board name) | iNES mapper 0: 16 or 32 KiB of PRG ROM and 8 KiB of CHR, no registers; `Mappers::Nrom`. | [NROM](https://www.nesdev.org/wiki/NROM) |
| NTSC | National Television System Committee | The video standard of North American and Japanese consoles; the timing this project emulates. | [Cycle reference chart](https://www.nesdev.org/wiki/Cycle_reference_chart) |
| OAM | Object Attribute Memory | PPU-internal memory with the sprite display list: 64 sprites × 4 bytes. | [PPU OAM](https://www.nesdev.org/wiki/PPU_OAM) |
| Open bus | — | Reading an address no device answers; the result is usually the last value on the data bus. | [Open bus behavior](https://www.nesdev.org/wiki/Open_bus_behavior) |
| PAL | Phase Alternating Line | The European video standard, with different clock ratios and frame timing; not emulated (backlog). | [Cycle reference chart](https://www.nesdev.org/wiki/Cycle_reference_chart) |
| Palette | — | 6-bit colour indices (one of 64 colours); 4 background and 4 sprite palettes at `$3F00-$3F1F`. | [PPU palettes](https://www.nesdev.org/wiki/PPU_palettes) |
| Pattern table | — | PPU memory defining tile shapes (the CHR data). | [PPU pattern tables](https://www.nesdev.org/wiki/PPU_pattern_tables) |
| PPU | Picture Processing Unit | Generates the video signal, 240 lines of pixels. | [PPU](https://www.nesdev.org/wiki/PPU) |
| PPUCTRL … PPUDATA | PPU registers | `$2000` PPUCTRL, `$2001` PPUMASK, `$2002` PPUSTATUS, `$2003` OAMADDR, `$2004` OAMDATA, `$2005` PPUSCROLL, `$2006` PPUADDR, `$2007` PPUDATA; `$4014` OAMDMA. | [PPU registers](https://www.nesdev.org/wiki/PPU_registers) |
| Pre-render scanline | — | Scanline 261 (also called −1), before the visible ones: VBlank, sprite 0 hit and overflow are cleared at its dot 1, and on odd frames with rendering enabled its last dot is skipped. | [PPU rendering](https://www.nesdev.org/wiki/PPU_rendering), [PPU frame timing](https://www.nesdev.org/wiki/PPU_frame_timing) |
| PRG | Program (memory) | The cartridge memory on the CPU side: PRG ROM (16 KiB units in iNES) with the program, and PRG RAM (also called WRAM), usually at `$6000-$7FFF`. | [iNES](https://www.nesdev.org/wiki/INES), [CPU memory map](https://www.nesdev.org/wiki/CPU_memory_map) |
| Quarter frame, half frame | — | The frame counter's two clocks: quarter frames clock the envelopes (and the triangle's linear counter), half frames the length counters and the sweeps, about 240 and 120 times a second. | [APU Frame Counter](https://www.nesdev.org/wiki/APU_Frame_Counter) |
| R0-R7 | Bank registers 0 to 7 (MMC3) | The eight bank registers MMC3's bank select chooses and bank data loads: R0 and R1 the 2 KiB CHR banks, R2-R5 the 1 KiB CHR banks, R6 and R7 the 8 KiB PRG banks; NESdev's names, kept in `Mappers::Mmc3::R6` and `R7`. | [MMC3](https://www.nesdev.org/wiki/MMC3) |
| RAM | Random-Access Memory | Readable and writable memory: the console's 2 KiB internal RAM at `$0000-$07FF`, and on some cartridges PRG RAM and CHR RAM. | [CPU memory map](https://www.nesdev.org/wiki/CPU_memory_map) |
| RDY | Ready | The 6502 input that halts the CPU while low; DMA pulls it. It changes what the unstable unofficial opcodes store, which the emulator does not model. | [CPU pinout](https://www.nesdev.org/wiki/CPU_pinout) |
| ROM | Read-Only Memory | The cartridge's PRG ROM and CHR ROM. By extension, a dumped cartridge image (an iNES file), as in "test ROM". | [iNES](https://www.nesdev.org/wiki/INES) |
| Sample buffer | — | The DMC's one-byte buffer between memory and its output unit: the memory reader fills it by DMA whenever it is empty and bytes remain, and the output unit empties it every eight timer clocks (`Apu::Dmc::MemoryReader`, `Apu::Dmc::OutputUnit`). | [APU DMC](https://www.nesdev.org/wiki/APU_DMC) |
| Scanline | — | One row of the frame; 262 per NTSC frame. | [PPU rendering](https://www.nesdev.org/wiki/PPU_rendering) |
| Secondary OAM | — | The PPU's 32-byte buffer of the (up to) 8 sprites selected for the next scanline; `Ppu::SecondaryOam`. | [PPU sprite evaluation](https://www.nesdev.org/wiki/PPU_sprite_evaluation) |
| Serial port (MMC1) | — | The MMC1's load register: five writes with bit 7 clear carry one bit each in bit 0, the fifth loads the register its address selects; a write with bit 7 set resets it, and a write on the cycle after another (the second write of a read-modify-write instruction) is ignored unless it is a reset. `Mappers::Mmc1::SerialPort`. | [MMC1](https://www.nesdev.org/wiki/MMC1) |
| Sprite 0 hit | — | A PPUSTATUS flag set when sprite 0 overlaps the background; games poll it to time mid-frame effects such as a fixed status bar. | [PPU registers](https://www.nesdev.org/wiki/PPU_registers) |
| Sprite overflow | — | The PPUSTATUS flag (bit 5) meant for a ninth sprite on a scanline; the hardware's search for it reads OAM "diagonally" after the eighth sprite, so it gives false positives and negatives (`Ppu::OverflowSearch`). | [PPU sprite evaluation](https://www.nesdev.org/wiki/PPU_sprite_evaluation) |
| Stall | — | CPU cycles spent halted while a DMA uses the bus: 513-514 for OAM DMA, 3-4 for a DMC fetch (`Cpu#halt`). | [DMA](https://www.nesdev.org/wiki/DMA) |
| Status flags | — | The CPU's P register, bits `NV1B DIZC`: N negative, V overflow, B break (not a real flag), D decimal, I interrupt disable, Z zero, C carry. | [Status flags](https://www.nesdev.org/wiki/Status_flags) |
| Sweep | — | The pulse channel unit that slides the timer's period up or down on half frames, and mutes the channel when the period is below 8 or its target above `$7FF`; `Apu::Sweep`. | [APU Sweep](https://www.nesdev.org/wiki/APU_Sweep) |
| SxROM, SUROM | — (Nintendo's board names: SAROM, SNROM, SUROM, SXROM and others) | The MMC1 boards. SUROM has 512 KiB of PRG ROM: CHR bank 0 bit 4 selects the 256 KiB outer bank the PRG windows see, the fixed bank included. | [MMC1](https://www.nesdev.org/wiki/MMC1) |
| TxROM | — (Nintendo's board names: TBROM, TGROM, TKROM, TLROM, TSROM, TVROM and others) | The MMC3 boards; TVROM and TR1ROM have four-screen VRAM, TKROM, TNROM and TSROM 8 KiB of PRG RAM. | [TxROM](https://www.nesdev.org/wiki/TxROM) |
| UxROM | — (Nintendo's board names, UNROM and UOROM) | iNES mapper 2: a switchable 16 KiB PRG ROM bank at `$8000`, the last bank fixed at `$C000`, 8 KiB of CHR RAM; `Mappers::Uxrom`. | [UxROM](https://www.nesdev.org/wiki/UxROM) |
| v, t, x, w | Current VRAM address, temporary VRAM address, fine X scroll, write toggle | The PPU's internal scroll registers (15, 15, 3 and 1 bits), named by their letters on NESdev. Code spells them out in `Ppu::ScrollRegisters`: `vram_address`, `temporary_address`, `fine_x`, `second_write?`. | [PPU scrolling](https://www.nesdev.org/wiki/PPU_scrolling) |
| VBlank | Vertical blanking | Scanlines 241–260, when the PPU makes no memory accesses; the VBlank flag is set at scanline 241, dot 1. | [PPU rendering](https://www.nesdev.org/wiki/PPU_rendering) |
| VRAM | Video RAM | The PPU's nametable memory; on the console, the 2 KiB CIRAM. | [PPU nametables](https://www.nesdev.org/wiki/PPU_nametables) |
| φ1, φ2 | Phase 1, phase 2 | The two halves of a CPU cycle. The NMI edge detector samples the line during φ2, so the emulator stamps a /NMI change with the first CPU cycle whose φ2 sees it. | [CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts) |

## Computing terms

Standard acronyms used by the tooling around the emulator (the test ROM harness, the benchmark and the frontends),
kept in names because they are what the libraries and protocols call them.

| Term | Stands for | Meaning | Reference |
|---|---|---|---|
| Box filter | — | The resampler's average: each output sample is the mean of the input levels of its period (`Audio::Resampler`, plan 24). | [Moving average](https://en.wikipedia.org/wiki/Moving_average) |
| CRC | Cyclic Redundancy Check | The 32-bit checksum that closes every PNG chunk, computed over its type and data (`Zlib.crc32`). | [PNG](https://www.w3.org/TR/png-3/) |
| DC | Direct Current | A constant offset in a signal; the NES's high-pass filter removes the mixer's (`Audio::HighPassFilter`). | [DC bias](https://en.wikipedia.org/wiki/DC_bias) |
| FFI | Foreign Function Interface | Calling a C library from Ruby without a compiled extension: the `ffi` gem declares each function's signature and calls it at run time. The windowed backend's gem, `raylib-bindings`, is an FFI binding (plan 17). | [Ruby-FFI](https://github.com/ffi/ffi) |
| HTTP | Hypertext Transfer Protocol | The protocol the test ROM downloader speaks; a `200` status is a delivered file. | [RFC 9110](https://www.rfc-editor.org/rfc/rfc9110) |
| JIT | Just-In-Time (compiler) | A compiler that turns Ruby methods into machine code while the program runs. Ruby 4.0.9 ships two, YJIT and ZJIT, both off by default; the benchmark (plan 10) measures each against the interpreter. | [YJIT](https://docs.ruby-lang.org/en/master/yjit/yjit_md.html) |
| JSON | JavaScript Object Notation | The one-line format `bench/cpu.rb` prints its measurement in, for the bench rake tasks to collect. | [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259) |
| KiB | Kibibyte | 1024 bytes, the unit of every NES memory size in the code and the docs (`ONE_KIB`, `TWO_KIB` in `Mappers::Mmc3`). | [IEC binary prefixes](https://en.wikipedia.org/wiki/Binary_prefix) |
| High-pass, low-pass filter | — | A filter that lets frequencies above (high-pass) or below (low-pass) its cut-off through; first order means one RC stage, 3 dB down at the cut-off. The NES has a high-pass at 90 Hz and a low-pass at 14 kHz (plan 24). | [APU Mixer](https://www.nesdev.org/wiki/APU_Mixer) |
| Nyquist frequency | — | Half the sample rate (24 kHz at 48 kHz), the highest frequency samples can carry; discrete filters drift from their analogue models near it. | [Nyquist frequency](https://en.wikipedia.org/wiki/Nyquist_frequency) |
| PCM | Pulse-Code Modulation | Sound as a series of sample values; here signed 16-bit integers, 48 000 per second (`Audio::SAMPLE_RATE`). | [WAVE format](https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html) |
| PNG | Portable Network Graphics | The image format of the headless frontend's screenshots (`Frontends::Png`): a signature, then chunks (IHDR, IDAT, IEND), the pixels compressed with zlib. | [PNG](https://www.w3.org/TR/png-3/) |
| RC | Resistor-Capacitor | The circuit of a first-order filter; its time constant RC = 1 / (2π × cut-off) sets the filter's coefficient (`Audio.time_constant`). | [Low-pass filter](https://en.wikipedia.org/wiki/Low-pass_filter#Discrete-time_realization) |
| RGB | Red, Green, Blue | A colour as its three 8-bit intensities; `Frontends::Palette` turns each pixel into 3 such bytes. | [PPU palettes](https://www.nesdev.org/wiki/PPU_palettes) |
| RIFF | Resource Interchange File Format | The chunked container a WAV file is: a `RIFF` chunk holding the `WAVE` ID, then the `fmt ` and `data` chunks. | [WAVE format](https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html) |
| SHA-256 | Secure Hash Algorithm, 256-bit | The digest the test ROM manifest records for each file, and the headless frontend for each frame; a matching digest means the bytes are the expected ones. | [FIPS 180-4](https://csrc.nist.gov/pubs/fips/180-4/upd1/final) |
| SSL | Secure Sockets Layer | Name kept by Ruby `Net::HTTP` (`use_ssl:`) for an encrypted (TLS) connection. | [Net::HTTP](https://docs.ruby-lang.org/en/master/Net/HTTP.html) |
| Underrun | — | The audio device asks for samples the stream does not have; raylib plays silence then, so a slow emulator's music has gaps (plan 24, decision 2). | [raudio.c](https://github.com/raysan5/raylib/blob/master/src/raudio.c) |
| URL | Uniform Resource Locator | The address of a file on the web, e.g. a test ROM at one of the manifest sources. | [RFC 3986](https://www.rfc-editor.org/rfc/rfc3986) |
| WAV | Waveform Audio File Format | The headless frontend's audio file (`Frontends::Wav`): little-endian RIFF chunks, mono 16-bit PCM. | [WAVE format](https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html) |
| YAML | YAML Ain't Markup Language | The format of the test ROM manifest (`spec/fixtures/test_roms.yml`) and of the headless frontend's input script. | [YAML](https://yaml.org/) |
| YJIT | — (Yet another Ruby JIT, by its authors) | CRuby's lazy basic-block-versioning JIT, enabled with `--yjit`. | [YJIT](https://docs.ruby-lang.org/en/master/yjit/yjit_md.html) |
| ZJIT | — (the name is not expanded by its documentation) | CRuby's newer method-based JIT, enabled with `--zjit`. | [ZJIT](https://docs.ruby-lang.org/en/master/zjit_md.html) |

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

### low-bits

- Inline: `value & MASK`, where the mask is a run of ones from bit 0 (`COLOUR_MASK = 0x3F` keeps 6 bits)
- Off the hot path: `Bits.low_bits(value, MASK)`
- Keeps only the bits a narrower register or memory cell holds: a palette entry stores "a 6-bit color value"
  ([PPU palettes](https://www.nesdev.org/wiki/PPU_palettes)), so `$FF` is stored as `$3F`. wrap-to-byte and
  wrap-to-word are the 8- and 16-bit cases, named apart because the intent there is an overflow.

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

- Inline: `(byte >> NIBBLE_WIDTH) & NIBBLE_MASK` (`NIBBLE_WIDTH = 4`, `NIBBLE_MASK = 0x0F`); `byte >> NIBBLE_WIDTH`
  alone when the value is already a byte, as the opcode `Cpu::Dispatch` selects its row with
- Off the hot path: `Bits.high_nibble(byte)`
- The upper 4 bits of a byte as a number `0-15` (`$4A` → `$4`); the low 4 bits never influence it. The iNES header
  keeps the mapper number's halves in the high nibbles of bytes 6 and 7 ([iNES](https://www.nesdev.org/wiki/INES)).

### combine-nibbles

- Inline: `(high << NIBBLE_WIDTH) | low`
- Off the hot path: `Bits.combine_nibbles(low: 0x1, high: 0x2)` → `0x21`
- Builds a byte from its two 4-bit halves. Keyword arguments keep the order of the halves explicit.

### bit-field

- Inline: `(value & FIELD_MASK) >> FIELD_SHIFT`
- Off the hot path: `Bits.bit_field(value, mask: FIELD_MASK, shift: FIELD_SHIFT)`
- Reads a group of adjacent bits as a number of its own: address bits 10-11 (`NAMETABLE_SELECT_MASK = 0x0C00`,
  shift 10) number the logical nametable `0-3` ([PPU nametables](https://www.nesdev.org/wiki/PPU_nametables)).
  high-nibble is the case of the upper 4 bits of a byte.

### place-bit-field

- Inline: `(register & ~FIELD_MASK) | ((value << FIELD_SHIFT) & FIELD_MASK)`, often over two tagged lines: the field
  moved into place first (`field = (value << FIELD_SHIFT) & FIELD_MASK`), then merged
  (`(register & ~FIELD_MASK) | field`)
- Off the hot path: `Bits.place_bit_field(register, value, mask: FIELD_MASK, shift: FIELD_SHIFT)`
- Writes a number into a group of adjacent bits, leaving the others untouched: the PPU's register writes copy bits
  of the value into fields of `t` ([PPU scrolling](https://www.nesdev.org/wiki/PPU_scrolling)).

### set-flag

- Inline: `register | FLAG`
- Off the hot path: `Bits.set_flag(register, FLAG)`
- Turns the flag's bit on, leaving the others untouched.

### clear-flag

- Inline: `register & ~FLAG`
- Off the hot path: `Bits.clear_flag(register, FLAG)`
- Turns the flag's bit off, leaving the others untouched; with a field's mask (`COARSE_X_MASK`), it clears the whole
  field. (`~FLAG` is negative in Ruby, but and-ing it with a non-negative register keeps the result non-negative and
  within the register's width.)

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

### bitwise-and

- Inline: `first & second`
- Off the hot path: the same expression; the operator is the 6502's own `AND`, so there is no helper.
- Keeps the bits set in both values (`$CC & $AA` → `$88`). The instruction `AND` combines A with memory this way
  ([Instruction reference](https://www.nesdev.org/wiki/Instruction_reference)).

### bitwise-or

- Inline: `first | second`
- Off the hot path: the same expression; no helper (the 6502's `ORA`).
- Keeps the bits set in either value (`$CC | $AA` → `$EE`).

### bitwise-exclusive-or

- Inline: `first ^ second`
- Off the hot path: the same expression; no helper (the 6502's `EOR`).
- Keeps the bits set in exactly one of the values (`$CC ^ $AA` → `$66`).

### invert-byte

- Inline: `value ^ BYTE_MASK`
- Off the hot path: `Bits.invert_byte(value)`
- Flips every bit of a byte (`$30` → `$CF`), staying within `0-255` (unlike `~value`, which is negative in Ruby).
  `SBC` is `ADC` with the operand inverted this way: it "subtracts 1 more when carry is _clear_"
  ([Instruction reference](https://www.nesdev.org/wiki/Instruction_reference)).

### signed-overflow

- Inline: `sign_flips = (result ^ first) & (result ^ second)`, then `sign_flips.anybits?(SIGN_BIT)`
- Off the hot path: `Bits.signed_overflow?(first, second, result)`
- True when the result's sign differs from the signs of both addends: two positives that sum to a negative, or two
  negatives that sum to a positive. It is the `ADC` overflow flag, `V = (result ^ A) & (result ^ memory) & $80`
  ([Instruction reference](https://www.nesdev.org/wiki/Instruction_reference),
  [The 6502 overflow flag explained](http://www.righto.com/2012/12/the-6502-overflow-flag-explained.html)).

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

### add-within-page

- Inline: `(base & PAGE_MASK) | ((base + offset) & BYTE_MASK)`, or with the wrapped sum already at hand,
  `(base & PAGE_MASK) | (sum & BYTE_MASK)`
- Off the hot path: `Bits.add_within_page(base, offset)`
- Adds to the low byte only, keeping the base's page: `$12FF + 1` → `$1200`. The 6502's indexed modes read this
  address before fixing the high byte, a dummy read ("it may be smaller by $100", [6502_cpu.txt](https://www.nesdev.org/6502_cpu.txt)).

### page-crossed

- Inline: `(first & PAGE_MASK) != (second & PAGE_MASK)` (`PAGE_MASK = 0xFF00`)
- Off the hot path: `Bits.page_crossed?(first, second)`
- True when two addresses fall in different 256-byte pages. Indexed reads that cross a page cost the CPU one extra
  cycle ([CPU addressing modes](https://www.nesdev.org/wiki/CPU_addressing_modes)).
