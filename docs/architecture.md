# Architecture

How ruby-nes is shaped and why. This document is the **single source of truth** for the architecture and the coding
conventions; `CLAUDE.md` only summarises it, and plans record the history of each decision. When a later plan changes
a decision, it updates this document and its [Decisions log](#decisions-log). Acronyms and bit-operation tags used in
the code are explained in [`GLOSSARY.md`](GLOSSARY.md).

## Purpose

ruby-nes emulates an NTSC Nintendo Entertainment System in pure Ruby. It is a study project: correctness is checked
against test ROMs, and speed is measured under the interpreter, YJIT, ZJIT and (as an experiment) the Spinel AOT
compiler. The design favours code that is easy to read and easy for a JIT or an AOT compiler to optimise.

## Components

```text
+----------------------------------------------------------------------------+
| Console: owns every component and runs the clock                           |
|   Cpu#step -> cycles;  Ppu catches up 3 dots per cycle, also before every  |
|   access to its registers;  Apu catches up 1 cycle at a time, the same way |
+----------------------------------------------------------------------------+

  +-----+   CPU bus ($0000-$FFFF)
  | Cpu |----+-------------+---------------+------------------+-----------------+
  +-----+    |             |               |                  |                 |
         internal RAM   PPU registers   APU and I/O         test mode       Cartridge
         2 KiB          $2000-$3FFF     registers           (disabled)      $4020-$FFFF
         $0000-$1FFF       |            $4000-$4017         $4018-$401F     (mapper)
                           |            (APU, OAM DMA;                          |
                           v             controllers at $4016-$4017)            |
                        +-----+   PPU bus ($0000-$3FFF)                         |
                        | Ppu |----+------------------+-------------------------+
                        +-----+    |                  |                         |
                           |    palette RAM        nametables              pattern tables
                           |    $3F00-$3FFF        $2000-$2FFF             $0000-$1FFF
                           |    (inside the PPU)   (2 KiB VRAM, mirroring  (CHR ROM or RAM
                           v                        set by the cartridge)   on the cartridge)
                     frame buffer -----> Frontend (window, headless, ...)
```

- The **CPU** (inside the Ricoh 2A03) is a 6502 without decimal mode. The **APU** lives on the same chip and is
  reached through CPU bus registers.
- The **PPU** (Ricoh 2C02) draws the picture. It has its own 14-bit bus.
- The **cartridge** is wired to both buses: its mapper decides what PRG ROM/RAM the CPU sees and what CHR memory and
  nametable mirroring the PPU sees.
- Components talk **through buses**: the CPU never calls the PPU, it reads and writes `$2000-$2007`. Besides the
  buses there are exactly two other channels between components:
  1. **Interrupt lines** — NMI from the PPU, IRQ from the APU and mappers. The PPU tells each change of its /NMI
     output with the CPU cycle it happened on, `Cpu#nmi_line_changed(asserted, cycle)`, and the CPU polls it as the
     hardware does, at the end of an instruction's second-to-last cycle (plan 12). The IRQ line is a level set with
     `Cpu#assert_irq(source, cycle)` and `Cpu#release_irq(source, cycle)`: its sources combine as a wired-OR, each
     asserting and releasing its own bit (`Cpu::InterruptLines::MAPPER_IRQ` for the cartridge board, `FRAME_IRQ` for
     the APU's frame counter, `DMC_IRQ` for the DMC's sample end), and each change carries its CPU cycle, so the IRQ is
     polled at the same point as the NMI (plan 12, decision 3; plan 21, decision 5; plans 22 and 23). See Interrupt
     timing below.
  2. **CPU stall cycles** — OAM DMA (a write to `$4014`, plan 11) and DMC sample fetches (plan 23) halt the CPU for a
     number of cycles, through `Cpu#halt(stall_cycles)`: it adds the cycles at once and makes the next interrupt poll
     look back past them. The DMC calls it on the cycle it fetches (plan 23, decision 1); OAM DMA's stall is pulled by
     `Cpu#step` after each step, `bus.take_stall_cycles(@cycles)`, the argument being the CPU cycle the halt falls
     on.

## Buses

### CPU bus

Source: [CPU memory map](https://www.nesdev.org/wiki/CPU_memory_map).

| Range | Size | Device |
|---|---|---|
| `$0000-$07FF` | `$0800` | 2 KiB internal RAM (`$0100-$01FF` is the stack page) |
| `$0800-$1FFF` | `$1800` | three mirrors of `$0000-$07FF` |
| `$2000-$2007` | `$0008` | PPU registers |
| `$2008-$3FFF` | `$1FF8` | mirrors of `$2000-$2007`, repeating every 8 bytes |
| `$4000-$4017` | `$0018` | APU and I/O registers (including OAM DMA at `$4014` and the controller ports) |
| `$4018-$401F` | `$0008` | APU and I/O test functionality, normally disabled |
| `$4020-$FFFF` | `$BFE0` | cartridge space: usually PRG RAM at `$6000-$7FFF`, PRG ROM and mapper registers at `$8000-$FFFF` |

Interrupt vectors, from [CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts): NMI at `$FFFA`, reset at `$FFFC`,
IRQ and BRK at `$FFFE`. Reading an address no device answers returns
[open bus](https://www.nesdev.org/wiki/Open_bus_behavior), usually the last value on the data bus.

### Devices on the CPU bus

`CpuBus` has four slots, given as keywords to `CpuBus.new` and each defaulting to `CpuBus::Disconnected`:
`ppu_registers:` (`$2000-$3FFF`, handed the address already mirrored down to `$2000-$2007`), `apu_registers:`
(`$4000-$4015` and writes to `$4017`, the frame counter), `controller_ports:` (reads of `$4016`/`$4017`, writes to
`$4016`) and `mapper:` (`$4020-$FFFF`). `$4018-$401F` reach no device. The split of `$4000-$4017` mirrors the 2A03's
own decoding (plan 15, decision 1). A device answers:

- `cpu_read(address, data_bus)` → the byte left on the data bus after the read. A device that does not drive the bus
  at that address returns `data_bus` untouched (open bus); a register that drives only some bits keeps the others
  from `data_bus`. The bus stores every result as the next `data_bus`; writes do not change it (plan 04, decision 1).
  The `apu_registers:` slot is the exception: `$4015` "is internal to the CPU and so the external CPU data bus is
  disconnected when reading it" ([APU](https://www.nesdev.org/wiki/APU)), so the bus returns what the slot answers
  without storing it (plan 22, decision 2); the rest of the slot is open bus anyway.
- `cpu_write(address, value)`.

`CpuBus` also owns the **OAM DMA unit**, `CpuBus::OamDma` (plan 11, decision 2): a write to `$4014` starts it instead of
reaching the `apu_registers:` slot (reads of `$4014` still go to the slot). Its collaborators are the bus's own: it
reads the page through `CpuBus#read_for_dma` and writes each byte to `ppu_registers.cpu_write($2004, byte)`, so the
bytes land in OAM from OAMADDR on. The copy happens at once; the 513 or 514 cycles it costs come back through
`CpuBus#take_stall_cycles(halt_cycle)`. Get cycles are the even CPU cycles by convention (see Known gaps).

### Mapper interface

Every board in `Ruby::Nes::Mappers` (built by `Mappers.build(cartridge)` from the iNES mapper number) answers the CPU
device interface above plus:

| Method | Returns |
|---|---|
| `ppu_read(address)` | the pattern table byte, for `$0000-$1FFF` (the PPU bus never hands anything else) |
| `ppu_write(address, value)` | kept by CHR RAM, ignored by CHR ROM |
| `mirroring` | the nametable arrangement the board selects: `:horizontal`, `:vertical`, `:single_screen_lower`, `:single_screen_upper` or `:four_screen`, read by the nametables when they are built |
| `nametables=` | takes the PPU bus's `PpuBus::Nametables`, which give themselves to the board; the board tells them `mirroring_changed(mirroring)` whenever it selects an arrangement, through the base's private `mirroring=` (plan 30, decision 3) |
| `ppu_address(address)` | the PPU left `address` on its bus without reading or writing: v after a PPUADDR write or a PPUDATA access, outside rendering only, a deliberate divergence from the MMC3 page's "regardless of whether PPU is/is not rendering" (plan 21, decisions 1 and 10); only MMC3 watches it |
| `cpu=` | takes the CPU: MMC1's clock (its `cycles`, plan 20 decision 1) and MMC3's IRQ line (`assert_irq`/`release_irq`) |
| `ppu=` | takes the PPU: MMC3's A12 filter reads `Ppu#elapsed_dots` (plan 21, decision 2) |
| `earliest_irq_cycle(cycle)` | the earliest CPU cycle the PPU's fetches could make the board assert its IRQ, the PPU standing on `cycle`: `Mappers::Base::NEVER` (`Float::INFINITY`) by default, MMC3's from its counter (plan 28, decision 3); `PpuBus` hands it to the PPU's `sync_cycle` |
| `register_sync=` | takes `Console::PpuRegisterSync`, whose `catch_up` brings the PPU to the instruction's access cycle before every register write (plan 21, decision 6) |
| `battery_ram`, `battery_ram=` | a copy of the 8 KiB of PRG RAM, `$6000` first, when the board has PRG RAM and the header the battery flag (iNES flags 6 bit 1), else `nil`; and the bytes of a save copied into it, in the same array the CPU reads. Off the hot path: the window's battery save (plan 34), through `Console#battery_ram` |

`Console` wires `cpu=`, `ppu=` and `register_sync=` on every board. The IRQ is not a method of the board any more: a
board with one asserts and releases it on the CPU (plan 21, decision 5).

Every board is a `Mappers::Base` (plan 19, decision 1). The base reads PRG ROM through four 8 KiB windows (`$8000`,
`$A000`, `$C000`, `$E000`, picked by address bits 14-13) and CHR through eight 1 KiB windows (picked by address bits
12-10; plan 21, decision 8), each an offset into the cartridge's memory, kept by a `Mappers::BankWindows` per memory
(the base reads its preallocated offsets array directly). Out of the box they show the first and the last 16 KiB of PRG
ROM and the first 8 KiB of CHR: that is NROM as it comes. A board with registers overrides the private
`write_register(address, value)`, which receives every write to `$8000-$FFFF` once the PPU caught up (see the
interface above), and turns it into bank selections through `select_prg_bank(address, bank, size)` and
`select_chr_bank(address, bank, size)`: the bank `bank`, counted in banks of `size` bytes (a whole number of windows:
`PRG_HALF_AREA_SIZE`, `PRG_AREA_SIZE`, `CHR_HALF_AREA_SIZE`, `CHR_AREA_SIZE` or MMC3's 8, 2 and 1 KiB), from `address`
on. A bank past the end of the memory wraps around it, one window-sized piece at a time, off the hot path;
`last_prg_bank(size)` numbers the last bank of a size. PRG RAM at
`$6000-$7FFF` is 8 KiB when the board says so (`prg_ram: true`), and a board may turn it off at runtime
(`enable_prg_ram`, MMC1); without it, or off, the range is open bus. Mirroring is the header's until a board changes
it through the private `mirroring=` (AxROM, MMC1, MMC3), which tells the nametables; a header asking for four-screen
VRAM (flags 6 bit 3) makes it `:four_screen`, which MMC3 keeps and AxROM and MMC1 set over (plan 21, decision 7).

| Board | iNES | Registers (writes to `$8000-$FFFF`) | Bus conflicts | PRG RAM |
|---|---|---|---|---|
| `Nrom` | 0 | none | — | 8 KiB, always (plan 04, decision 2) |
| `Uxrom` | 2 | the whole byte selects the 16 KiB bank at `$8000`; `$C000` stays on the last bank | no | none |
| `Cnrom` | 3 | the byte, ANDed with the PRG ROM byte at the address, selects the 8 KiB CHR bank | yes | none |
| `Axrom` | 7 | bits 2-0 select the 32 KiB bank; bit 4 the single screen (0 lower, 1 upper) | no | none |
| `Mmc3` | 4 | even/odd pairs at `$8000`, `$A000`, `$C000`, `$E000`: bank select and data (R0-R7; 8 KiB PRG banks in two modes, 2 and 1 KiB CHR banks, CHR A12 inversion), mirroring (ignored on four-screen boards), PRG RAM protect (ignored, plan 21 decision 4), IRQ latch, reload, disable and enable of `Mmc3::IrqCounter` (the Sharp MMC3B/C "new" behaviour), which `Mmc3::A12Watcher` clocks on rising edges of PPU A12 low for 3 M2 cycles | no | 8 KiB, always |
| `Mmc1` | 1 | a serial port (`Mmc1::SerialPort`) loads Control (mirroring, PRG mode, CHR mode), CHR bank 0, CHR bank 1 and PRG bank, five writes each; bit 7 resets; a write on the cycle after another is ignored unless it resets; SUROM's 512 KiB take the outer bank from CHR bank 0 bit 4 | no | 8 KiB, off while PRG bank bit 4 is set |

Every register starts at 0 (plan 19, decision 6), except MMC1's Control, which starts at `$0C` as after a reset (plan
20, decision 4). MMC3's mirroring is the header's until `$A000` is written.

### Controllers

`Input::ControllerPorts` answers the `controller_ports:` slot
([Controller reading](https://www.nesdev.org/wiki/Controller_reading)): a `$4016` write strobes both
`Input::Controller`s, a read of `$4016` clocks the first and a read of `$4017` the second. The ports drive bits 4-0
(a standard controller only D0; D4-D1 read 0) and keep bits 7-5 from the data bus
([Open bus behavior](https://www.nesdev.org/wiki/Open_bus_behavior)). `Console.new(cartridge, controllers:)` takes the
two controllers (two released ones by default) and `Console#controllers` returns them; the frontend sets the buttons
held with `Controller#buttons=`, a mask in report order (`Controller::BUTTONS`, bit 0 = A … bit 7 = Right). The core
does not filter opposite directions; the frontend does (plan 15, decision 2). OAM DMA never clocks them: it reads
through `CpuBus#read_for_dma`, where `$4000-$401F` is open bus ([DMA](https://www.nesdev.org/wiki/DMA)).

### APU

`Apu` answers the `apu_registers:` slot ([APU](https://www.nesdev.org/wiki/APU), plans 22 and 23): `$4000-$4013`
reach the five channels through a constant table indexed by address bits 4-2 (two `Apu::Pulse`s, `Apu::Triangle`,
`Apu::Noise`, `Apu::Dmc`), `$4015` enables the channels and reads `IF-D NT21` (the DMC and frame interrupt flags, the
DMC's bytes remaining, the four length counters above 0, bit 5 from the data bus), and a `$4017` write goes to
`Apu::FrameCounter`. A pulse is an `Apu::Timer` clocking an `Apu::DutySequencer`, an `Apu::Envelope`, an `Apu::Sweep`
(pulse 1 negating with ones' complement, pulse 2 with two's) and an `Apu::LengthCounter`; its output is 0-15. The
triangle's timer ticks every CPU cycle and clocks an `Apu::TriangleSequencer` (32 steps) only while its
`Apu::LinearCounter` and its length counter are above 0; it outputs the step it stands on, and ultrasonic periods play
like any other (plan 23, decision 4). The noise's timer clocks an `Apu::NoiseShiftRegister` (15 bits, starting at 1,
decision 6); it outputs its envelope's volume unless bit 0 of the register is set or its length counter is 0. The
DMC's timer clocks its `Dmc::OutputUnit`, which takes a byte from the `Dmc::MemoryReader`'s buffer every eight clocks
and moves a 7-bit level by 2 per bit; the reader fills the buffer by DMA at the `Dmc::Sample`'s address, halting the
CPU 3 cycles for a load (on the `$4015` write, decision 3) and 4 for a reload (decision 2), and the sample's end sets
the DMC's `Apu::InterruptFlag` (`DMC_IRQ`) unless it loops. The noise and DMC tables are in CPU cycles; their timers,
ticked every APU cycle, reload half the entry minus 1. The frame counter runs NTSC mode 0 (4-step) or mode 1 (5-step)
from two constant tables per mode in CPU cycles (the APU Frame Counter page's APU cycles × 2, + 1 on PUT), tells the
APU's `quarter_frame` (envelopes, the linear counter) and `half_frame` (length counters, sweeps), and in mode 0
triggers the frame's `Apu::InterruptFlag`, which asserts `FRAME_IRQ` on the CPU unless inhibited (`$4017` bit 6). A
`$4017` write takes effect 3 CPU cycles after a write on an odd cycle and 4 after one on an even cycle, with a quarter
and a half frame at once in mode 1 (plan 22, decision 5). A `$4015` read clears the frame flag, even on the cycle it was
set (plan 22, decision 7), and leaves the DMC's; a `$4015` write clears the DMC's. `Apu#output` is
`Apu::Mixer.mix` of the five outputs, the [APU Mixer](https://www.nesdev.org/wiki/APU_Mixer) page's lookup tables
(decision 5), computed on demand (decision 8). Power-up is mode 0 from cycle 0 with every channel disabled; reset
disables the channels, clears both interrupt flags, writes `$4017`'s last value again, as the readme of blargg's
`apu_reset` says (plan 22, decision 4), and puts the triangle on its first step and the DMC level to its bit 0
([CPU power up state](https://www.nesdev.org/wiki/CPU_power_up_state)).

**Runs of quiet cycles** (plan 29). `Apu#catch_up` does not run every cycle one by one: the cycles before the next one
on which a slow unit changes are quiet, and the slow units skip them at once, the triangle and the noise going through
them clock by clock (below, plan 33). Each unit tells how far it is quiet: `FrameCounter#quiet_cycles` (until its next
step or a pending `$4017` write takes effect), and each channel's `quiet_ticks`, the ticks before its timer's next
clock that can change its output (`Timer#ticks_before_next_clock`, or `#ticks_before_clock` for the DMC's output
cycle); the pulses' and the DMC's bound the run, the triangle's and the noise's give their first clock within it.
A muted channel answers `Apu::NEVER`: a pulse with its length counter at 0, its sweep muting it or a volume of 0, the
noise with its length counter at 0 or a volume of 0, the triangle with a counter at 0; their output cannot change
until a frame counter step or a register write, which end runs anyway. The DMC is quiet until its timer's next clock
while it plays a byte, until the clock that starts its next output cycle while it is silent, and for good while it is
silent with an empty buffer and no sample. The pulse, noise and DMC timers tick on get cycles, so their ticks become CPU
cycles through `Apu::GetCycles`. A skip (`skip(ticks)`, `Timer#skip`) leaves each unit as that many ticks would,
clocking its sequencer on each reload; a stopped triangle's timer moves its counter without a call per clock
(`Timer#skip_without_clocking`), since its period is often 0, a clock every cycle. The cycle with a change runs as
before, its mix handed to the resampler on its own.

**Slow and fast units** (plan 33). Only the slow units bound the runs: the frame counter, the two pulses (a period
below 8 mutes a pulse, [APU Sweep](https://www.nesdev.org/wiki/APU_Sweep)) and the DMC. The triangle, whose timer is
clocked every CPU cycle down to a period of 0 (games silence it that way, a clock every cycle), and the noise, down to
4 CPU cycles a clock, would cut runs down to 1-4 cycles: in Super Pitfall's sound effects they made the APU run all
29 780 cycles of a frame one by one. Within a run, `Apu::FastChannels` takes them clock by clock instead: the first
clock from `quiet_ticks` (a stopped triangle or a silent noise skip the run as before), the next ones every
`ticks_per_clock` (`Timer#ticks_per_clock`, in get cycles for the noise), each one stepping its channel (`step`) in
cycle order, a clock on the run's end left to the next run, and each timer moved through the run without clocking
afterwards (`skip_without_clocking`). With audio on, the APU hands it the pulses' and the DMC's outputs, which stand
still through the run, and it hands the resampler the run in parts, the mix anew from each clock's cycle on: the parts
cycle by cycle would give, so the samples are unchanged. `Audio::Resampler#add_run` takes parts of any length, one
cycle going straight to `#add`.

### Audio

`Ruby::Nes::Audio` turns the APU's output into the samples a speaker plays (plan 24): signal processing in the core,
not hardware. With a sample rate (`Console.new(cartridge, audio_sample_rate:)`, `Audio::SAMPLE_RATE` = 48 000, the
macOS output device's own rate, decision 1), the APU's catch-up hands `Apu#output` of every CPU cycle to an
`Audio::Resampler`, a box filter: each output sample is the mean of the levels of the cycles since the previous one,
the period kept as an exact fraction (the CPU clock is 945 000 000 / 528 Hz, the master clock "236.25 MHz ÷ 11 by
definition" ÷ 12, [Cycle reference chart](https://www.nesdev.org/wiki/Cycle_reference_chart)), so the samples never
drift. A run of quiet cycles hands it one level for many cycles (`Resampler#add_run`, plan 29): it splits the run where
samples are due and still adds the level once per cycle, so the float sum is bit for bit the one of as many `add`
calls. `Audio::OutputStage` runs the NES's output circuit on each sample, "A first-order high-pass filter at 90 Hz"
then "A first-order low-pass filter at 14 kHz" ([APU Mixer](https://www.nesdev.org/wiki/APU_Mixer); the page lists no
high-pass at 440 Hz), as `Audio::HighPassFilter` and `Audio::LowPassFilter` in the discrete RC form, and rounds the
result to a signed 16-bit sample (a 0.0-1.0 level leaves the high-pass within (-1, 1), so no clamping) into an
`Audio::SampleBuffer`, allocated once, which `Console#audio_samples` drains once per frame (about 799 samples). Without
a sample rate the APU has no resampler and mixes nothing (decision 6). The window plays the samples paced by them
(Frontends, below); the headless run writes them as a WAV file.

### PPU bus

Source: [PPU memory map](https://www.nesdev.org/wiki/PPU_memory_map). The PPU addresses 14 bits (`$0000-$3FFF`).

| Range | Size | Contents | Mapped by |
|---|---|---|---|
| `$0000-$0FFF` | `$1000` | pattern table 0 | cartridge |
| `$1000-$1FFF` | `$1000` | pattern table 1 | cartridge |
| `$2000-$2FFF` | `$1000` | nametables 0–3 (each `$03C0` of tiles + `$0040` attribute table) | cartridge (normally the 2 KiB internal VRAM, mirrored) |
| `$3000-$3EFF` | `$0F00` | unused in the table; the page's hardware notes say it is usually a mirror of `$2000-$2EFF` | cartridge |
| `$3F00-$3F1F` | `$0020` | palette RAM | internal to the PPU |
| `$3F20-$3FFF` | `$00E0` | mirrors of `$3F00-$3F1F` | internal to the PPU |

`PpuBus` (plan 11) decodes the range and delegates: pattern tables to the mapper's `ppu_read`/`ppu_write`,
`$2000-$3EFF` to `PpuBus::Nametables`, `$3F00-$3FFF` to `PpuBus::PaletteRam`.

- **Nametables** hold 4 KiB of VRAM: the console's 2 KiB of CIRAM (pages 0 and 1) and the 2 KiB a four-screen board
  brings (pages 2 and 3). Address bits 10-11 pick the logical nametable; the board's mirroring, told on every change
  (plan 30, decision 3), picks its physical page ([Mirroring](https://www.nesdev.org/wiki/Mirroring), whose names the
  iNES header follows; the PPU nametables page names the arrangements the other way round):

  | `mirroring` | `$2000` | `$2400` | `$2800` | `$2C00` |
  |---|---|---|---|---|
  | `:horizontal` | 0 | 0 | 1 | 1 |
  | `:vertical` | 0 | 1 | 0 | 1 |
  | `:single_screen_lower` | 0 | 0 | 0 | 0 |
  | `:single_screen_upper` | 1 | 1 | 1 | 1 |
  | `:four_screen` | 0 | 1 | 2 | 3 |

- **Palette RAM** holds 32 entries of 6 bits ("a 6-bit color value"); entry 0 of each sprite palette (`$3F10`, `$3F14`,
  `$3F18`, `$3F1C`) is the same storage as entry 0 of the matching background palette: "writing to either one updates
  the same internal storage" ([PPU palettes](https://www.nesdev.org/wiki/PPU_palettes)).

### PPU registers

`Ppu` answers the `ppu_registers:` slot ([PPU registers](https://www.nesdev.org/wiki/PPU_registers)). It decodes the
eight registers and keeps the PPU's I/O latch (open bus, without decay); behind it, `Ppu::ScrollRegisters` holds v, t,
x and w and applies each row of the "Register controls" table of
[PPU scrolling](https://www.nesdev.org/wiki/PPU_scrolling), `Ppu::Oam` holds OAM and OAMADDR, and `Ppu::DataPort` is
PPUDATA: the read buffer, the palette exception and the increment of v. `Ppu` tells the port the increment (PPUCTRL
bit 2) and the greyscale (PPUMASK bit 0) when those registers are written. `Ppu#cpu_read` ignores the CPU's data bus:
the PPU answers from its own latch.

### Rendering

`Ppu#catch_up` runs the dots as ranges within a scanline (plan 28, decision 4). Each range starts on the dot the frame
timing just entered, with its events, and ends on the frame timing's last quiet dot (`FrameTiming#last_quiet_dot`) or
the catch-up's target. `Ppu::Renderer#run_dots(scanline, first_dot, last_dot)` runs it. The renderer takes the
scanline's steps from `Ppu::RenderSchedule#line`, one frozen array of flags per kind of scanline (visible,
pre-render, forced blank, idle, blank), and runs each dot's steps as one pipeline (plan 25, decision 7):
`Ppu::BackgroundFetcher` makes the nametable, attribute and pattern fetches from v (the attribute's address and
quadrant from two load-time tables indexed by v's low 12 bits), the renderer's own shift registers hold the two tiles
in flight and give the 4-bit pixel under fine X, `Ppu::ScrollRegisters` increments and copies v, and
`Ppu::PixelComposer` composes the background's and the sprites' entries and stores the pixel into the picture's drawn
frame through the picture's colour of each palette entry (`Ppu::Picture#colours`, rebuilt when palette RAM, greyscale
or emphasis change). The pixel of dot 1-256 goes to x = dot − 1. A tile of a visible line whose 8 dots the range
covers (`RenderSchedule::WHOLE_TILE` on its first dot) runs as one unrolled sequence: the reload, the window of 8
pixels under fine X (each register's byte (register × 2^fine X) >> 8, spread one bit per nibble by a load-time table
per register, 8 pixels of 4 bits in 32 bits), the composer drawing them in one call, the 8 shifts as one, the four
fetches, coarse X, and Y on dot 256. A layer's first visible column is 0, 8 or 256, so it shows in a whole tile or in
none of it: the background's hidden tile is a window of 0, and a tile whose sprites are hidden draws the background
alone, as does a tile the sprite line flags clear (`SpriteRenderer#occupied_tiles`, one flag per 8 columns, set
where an opaque sprite pixel lies). A visible line's sprite slot whose 8 dots the range covers (`WHOLE_SLOT` on 257,
265, …, 313) runs its first dot's own steps only where it has more than the slot's (257), then
`SpriteRenderer#run_slot` resets OAMADDR once and makes the two fetches with the clock on their dots and the load. The
next line's two tiles (`WHOLE_NEXT_LINE_TILE` on 321 and 329, both rendering lines) run as a whole tile without its
pixels: the reload where the dot has one, the 8 shifts as one, the four fetches and coarse X. The other dots run one
at a time (plan 28, decision 6; plan 30, decisions 2, 6 and 7; plan 31, decisions 1-3 and 5).

The dot clock (`Ppu::DotClock`) holds the PPU's elapsed dots, which MMC3's A12 watch reads through
`Ppu#elapsed_dots`. The Ppu ticks it into each range and sets it to the range's last dot. The renderer sets it to
each dot's count before that dot's fetches, and the sprite renderer, which shares it, before a whole slot's fetches,
so the board sees the dot of every fetch inside a range (plan 28, decision 5; plan 31, decision 3).

Sprites (plan 14): the renderer hands the sprite steps to `Ppu::SpriteRenderer`. At dot 257 of each visible line it
clears `Ppu::SpriteLine` and `Ppu::SpriteEvaluation` selects the next line's sprites from OAM into `Ppu::SecondaryOam`
(up to 8, `Ppu::SpriteRows` deciding "in range"); with 8 found, `Ppu::OverflowSearch` scans for a ninth with the
hardware's diagonal bug and `Ppu::SpriteStatus` keeps the flag. The pre-render line evaluates nothing, and lines
with rendering disabled only clear the line buffer, since nothing is fetched for them. Dots 261 + 8k and
263 + 8k fetch each slot's pattern bytes (`Ppu::SpriteFetcher`, through `Ppu::SpritePatternAddress::EightByEight` or
`::EightBySixteen`, the strategy `SpriteRenderer#tall_sprites=` selects, which also gives the evaluation its height;
empty slots fetch tile `$FF`), and on visible lines the row
goes into the line buffer, front to back, the first opaque pixel of each column kept with its priority and a sprite 0
mark. OAMADDR is 0 on dots 257-320. Each pixel, the renderer reads the background's 4 bits (transparent when the
pattern value is 0) and the sprite line's entry at x (`SpriteRenderer#line_entries`, one array for the life of the
line), each shown from its layer's first visible column (`Ppu::LayerVisibility`: layer disabled, leftmost 8 columns
hidden); where only one is opaque it is drawn, a sprite without its marks, and only where both are does
`Ppu::PriorityMultiplexer` pick one by NESdev's decision table (the composition is `Ppu::PixelComposer`'s), asking
`Ppu::SpriteZeroHit` (sprite 0, not x = 255).
`Ppu` decodes PPUCTRL bits 3, 4 and 5 and PPUMASK bits 0-4 and tells the renderer (both layers' visibility) and the
sprite renderer (pattern table and size), which pass each setting to its part; PPUSTATUS bits 6-5 are
`SpriteStatus`'s, cleared at dot 1 of the pre-render line.
`Ppu::Picture` also ORs PPUMASK's emphasis bits (5-7, told by `Ppu`) into bits 6-8 of every colour it precomputes,
and keeps two buffers, the one drawn swapped with the published one when `Ppu::FrameTiming` enters the post-render
scanline (plan 16, see Frame buffer contract).

### Frontends

`Frontends::Base` is the contract a frontend honours (`running?`, `button_states`, `present(frame_buffer)`,
`queue_audio(samples)`) and `Frontends::Driver` the loop they share: the buttons go to `Console#controllers`, the
console runs a frame, the frontend gets `Ppu#frame_buffer`. `Frontends::Palette` turns pixels into RGB with the 512
colours of NESdev's `2C02G_U_wiki.pal` (64 per emphasis combination), `Frontends::Png` encodes an image, and
`Frontends::Headless` runs N frames with an `Frontends::InputScript` (YAML, frame number to the buttons held from it
on), writes PNG screenshots and keeps each frame's SHA-256. The contract also has `paused?` and `reset_requested?`
(false by default, plan 18): the driver resets the console before a frame when asked, and while paused runs no frame
and presents the last completed one again, so a window keeps drawing, reading keys and pacing. The core never loads
any of them: `lib/ruby/nes.rb` requires no frontend file, and a spec checks it in a process of its own.

The windowed backend is raylib (plan 17, [backend comparison](backend-comparison.md)). `Frontends::Raylib` is an
adapter whose decisions live in collaborators specified on their own (plan 18): `Frontends::RaylibPicture` (the frame
on the GPU, plan 32: each pixel's value 0-511 uploaded as is, 2 bytes per pixel, into a grey-and-alpha texture, and a
GLSL fragment shader that looks its colour up in a 512×1 texture of `Frontends::Palette`'s colours, so the window draws
what `Frontends::Palette.rgb` gives with no RGB conversion on the CPU; its spec reads what it draws back from a render
texture), `Frontends::Viewport` (integer scale,
square or 8:7 pixels, overscan crop to lines 8-231), `Frontends::KeyConfig` and `Frontends::KeyBindings` (the `keys:`
and `gamepad:` sections of `~/.config/ruby-nes/config.yml`, each a `KeyConfig::Section`: actions to raylib key or
gamepad button names to codes, one action per input, the file's inputs taken from the defaults of other actions; the
gamepad binds controller buttons only, and `gamepad_mappings:` is SDL GameControllerDB text handed to raylib's
`SetGamepadMappings`, plan 36), `Frontends::Controls` (input codes to controller buttons, for keys and gamepad buttons
alike), `Frontends::Players` (plan 36: port 1 is the keyboard and gamepad 0 combined, port 2 is gamepad 1, a pad read
only while raylib says it is available, so plugging in and out needs nothing more; each port through
`Frontends::OppositeDirections`, Left+Right and Up+Down cancel) with `Frontends::Gamepad` (a pad's bound buttons and
its left stick past a dead zone of 0.5, `Frontends::StickDirections`), read through `Frontends::RaylibInput` (raylib's
key, gamepad and axis calls, loadable without the gem), `Frontends::Hotkeys` (Esc quits, P pauses, R resets, F
toggles the overlay, F5-F8 save, load and pick a save state slot), `Frontends::FrameRate` (the overlay's frames per second, beside the JIT running) and `Frontends::FramePacing` (sleep until the next deadline at
60.0988 Hz, deadlines a period apart so oversleeping never drifts, a period or more late restarts the schedule with no
catch-up burst). With audio (plan 24) the window paces by it instead: `Frontends::AudioPacing` queues each frame's
samples and, after the present, submits every whole 800-sample chunk to `Frontends::RaylibAudioStream` (two
sub-buffers, refilled only once played), waiting for room, so the emulator runs at the pace the speaker plays and the
audio clock is the master; less than a chunk waits for the next frame, and the queue keeps at most four chunks.
Chunks the stream has room for are submitted as soon as they are queued, without waiting. A stream with no room for
about two chunks' time (a dead audio device) loses the chunks queued rather than freezing the window, and a window whose
audio device does not open runs silent, paced by the timer. Before the stream opens the device,
`Frontends::AudioDeviceLatency` sets `PULSE_LATENCY_MSEC` to 15 on Linux unless the environment has it (plan 39): the
device must not ask for more samples at a time than fit beside one sub-buffer, or raylib serves the rest as silence
and the audio pacing slows down (the Pulse client's default, about 1024 samples, held the window at 53.4 fps). An
emulator slower than the speaker never waits: the stream runs dry between chunks and raylib zero-fills it, so an
underrun is a gap of silence (plan 24, decision 2; at plan 25's ~23 frames per second the music is choppy). While paused
the window queues a chunk of silence per frame, so the pacing goes on and the speaker is silent. `--no-audio` opens no
audio device and paces by the timer.
Its gem, `raylib-bindings` (FFI, the library built in for each platform), is in the optional `frontends` Gemfile group
(`bundle config set --local with frontends`), so neither the core nor CI needs it; specs that open its window are
tagged `frontend_library:` and skipped without it.
`exe/ruby-nes ROM [--jit=none|yjit|zjit] [--scale N] [--aspect square|8:7] [--crop-overscan] [--config PATH]
[--no-audio]` or `--headless [--frames COUNT] [--screenshot FRAME:PATH]... [--input SCRIPT] [--wav PATH]` is
`CommandLine`: the console makes audio only when the run plays or keeps it (`Options#audio_sample_rate`), and
`Frontends::Headless` keeps the samples and writes them with `Frontends::Wav` (mono 16-bit PCM) when it closes,
however the run ends; `CommandLine::Jit` enables the JIT at runtime (YJIT by default), `CommandLine::Window` reads the
key config (`CommandLine::ConfigFile`) and opens the window through `CommandLine::RaylibWindow`, which loads raylib
only then. The driver hands each frame's samples to `queue_audio` after running it and before presenting it.
`Frontends::Driver` tells a frame observer `frame_ran` after each frame it runs (`Driver::NoFrameObserver` by default).
The window's observer is the battery save's keeper (plan 34): `CommandLine::Window` asks
`Saves::BatteryKeeper.for(console:, directory:, rom_path:, error_output:)` and loads the save before it opens the
window. A console without battery RAM gets `Saves::NoBattery`, which does nothing, before the directory is asked
anything. Otherwise `Saves::Directory` says where the save is (`$XDG_DATA_HOME/ruby-nes`, else `.local/share/ruby-nes`
under `Dir.home`, as the key config's `~`; the save is `saves/<ROM file name>.sav`), and `Saves::BatteryFile` reads
and writes it (the raw 8 KiB; a missing file is no save, another size is `Saves::InvalidSave` and stops the run before
the window opens; a write goes to a temporary file of its own, created exclusively, flushed and renamed over the save,
about 2 ms with the `fsync`). The keeper writes the RAM every 300 frames and when the run ends, before the window
closes, each time only when it changed since the load or the last write; a periodic write that fails is a warning on
the error output and the game goes on, the last one raises. Headless runs never touch saves, so their digests stay
reproducible.

Save states (plan 35) are in four layers:

- **The console.** `Console#snapshot` writes its components with Marshal, and `Mappers::Base#marshal_dump` puts nil in
  place of the PRG ROM, and of the CHR when it is ROM. `Console#restore` loads them, gives the board its cartridge's
  ROM back (`Mappers::Base#reattach_rom`) and swaps the components in, so whoever holds the console keeps it.
- **The state's bytes.** `Saves::ConsoleState` writes a header, then the snapshot compressed with zlib. The header holds
  magic bytes, the format's version, the SHA-256 of the ROM, the sample rate (0 without sound: a console with sound
  holds more objects) and a fingerprint of the code. The fingerprint covers the console's shape (`Saves::Shape`: every
  reachable object's class and instance variable names) and the core's constants (`Saves::ConstantsDigest`), since a
  state carries the tables it points at by value. It restores only a state whose header matches the console, and
  checks before `Marshal.load` runs. A snapshot Marshal still cannot load is refused too, never a crash.
- **The files.** `Saves::StateFiles` keeps slots 0-9 as `states/<ROM file name>/<slot>.state` with a `<slot>.png`
  picture (`Frontends::Screenshot`). Both go through `Saves::AtomicFile`, as the battery save does.
- **The player's actions.** `Saves::StateSlots` holds the current slot, which starts on the latest one. `Frontends::Hotkeys`
  turns F5-F8 into `state_action`, and the driver hands that action and the frontend to the states before the frame,
  paused or not (`Driver::NoStates` by default, so headless runs never touch states). The frontend is told
  `notify(message)`, which the window draws for 120 frames (`Frontends::Notice`), and after a load `discard_audio`
  (`AudioPacing#clear`).

The game in the window is `CommandLine::Game` (plan 37): `load` (the battery keeper, before `ruby-nes ROM` opens the
window), `play(frontend)` (the driver with the keeper and the state slots) and `close` (the save written). The window
outlives a game in the ROM browser (plan 37), in two layers:

- **The browser's screen, in `Frontends::Browser`, loadable without raylib.** `RomList` lists the `.nes` files of a
  folder (hidden ones left out), each a `Rom` with its name and tags (`RomName`: the file name without its No-Intro
  tags), the reason it cannot run, read from its iNES header alone (a file that cannot be read included), and marks
  for its battery save and save states. `Menu` is told controller 1's buttons each frame: `ButtonPresses` turns held
  buttons into presses, the directions repeating after 20 frames and every 6, `Cursor` keeps the focus and the rows
  shown, and A or Start return the ROM to start; a folder with no ROM gets `EmptyMenu` instead. `Screen`
  composes the menu as an NES frame, 256 × 240 palette indices on the 8 × 8 grid, with `PixelFont`'s 8 × 8 glyphs, so
  the window draws it as it draws a game and its specs read it as text. `Preview` gives the game in focus a silent
  console of its own: its cached state (`PreviewCache`, `previews/<ROM SHA-256>.state`, a `Saves::ConsoleState`) is
  restored at once as the still picture; after 30 frames of rest the console runs a frame per menu frame, and from
  power-up `MotionWatch` counts the different pictures of each second (a frame buffer's hash) until 30 mark the moving
  picture, or a minute passes, and the state is cached there. A cartridge the preview cannot load gives its reason
  (`Preview#problem`), which the screen shows as it shows a ROM's own.
- **The loop, in `CommandLine`.** `CommandLine::Window#browse` reads the config, picks the folder (the command line's,
  else `roms_directory:`, else `roms/`), lists it and opens the window; `CommandLine::Browser` runs the menu, asking the
  window for a frame of silence each frame (`Frontends::Base#queue_silence`; while paused the window queues its own) so
  the audio keeps pacing it, plays the ROM started as a `Game` on a console of
  its own, and goes back to the list, read again, when the game ends. Escape ends the game (the hotkeys' quit), the
  window's close button (`Frontends::Base#closed?`) ends the browser, and `Frontends::Base#next_screen` starts the
  hotkeys and the queued audio over between screens.

`bench/frontends.rb` and `rake bench:frontends` run and time the backend unpaced; its tone still reaches the speaker,
as the audio pacing submits whatever the stream has room for when samples are queued.

## Clock

Sources: [Cycle reference chart](https://www.nesdev.org/wiki/Cycle_reference_chart),
[PPU frame timing](https://www.nesdev.org/wiki/PPU_frame_timing). NTSC only (PAL is in the backlog).

| Quantity | Value |
|---|---|
| Master clock | 21.477272 MHz (236.25 MHz ÷ 11) |
| CPU clock | master ÷ 12 = 1.789773 MHz |
| PPU dot | master ÷ 4 |
| PPU dots per CPU cycle | exactly 3 |
| Dots per scanline | 341 |
| Scanlines per frame | 262 (240 visible, 1 post-render, 20 vertical blanking, 1 pre-render) |
| Dots per frame | 89342; 89341 on odd frames with rendering enabled |
| CPU cycles per frame | 29780.5 with rendering enabled; 29780⅔ with rendering disabled |
| Frame rate | 60.0988 Hz |

**Odd-frame skipped dot:** with rendering enabled, each odd frame jumps from dot (339, 261) of the pre-render
scanline straight to (0, 0) of the first visible scanline. With rendering disabled no dot is skipped. The even/odd
flag toggles every frame either way.

## Clock model

**Register-access catch-up** (plan 12, decision 1; upgrade path 1 of the original instruction-level model):

1. `Cpu#step` charges an instruction's base cycles before running it, so while it runs `Cpu#cycles` is the cycle it
   ends on; indexed reads add their page-cross cycle while resolving the address, before the access.
2. Before every CPU access to `$2000-$3FFF`, `Console::PpuRegisterSync` (the device in the `ppu_registers:` slot)
   catches the PPU up to the start of the instruction's last cycle, `cycles - 1`: every non-read-modify-write
   instruction makes its data access on its last cycle ([6502_cpu.txt](https://www.nesdev.org/6502_cpu.txt)).
   Read-modify-write instructions on PPU registers, whose accesses span their last three cycles, are approximated.
3. After the step, `Console#step` catches the PPU up to the end of the instruction, `cycles * 3` dots. `Console#run_frame`
   does so only from the PPU's sync cycle on (step 7).
4. The PPU tells the CPU each change of /NMI with the first CPU cycle whose φ2 sample sees it: the edge detector
   "polls the status of the NMI line during φ2 of each CPU cycle" ([CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts)),
   which falls before a cycle's last dot, so a change on that dot counts for the next cycle (`(dot + 1) / 3`,
   calibrated with `ppu_vbl_nmi` 05-08). A line released within the cycle it rose in leaves no edge, which is how a
   `$2002` read or an NMI disable right after VBlank starts suppresses the NMI. The CPU takes an NMI only when its
   edge came before the previous instruction's last cycle, "the status of the interrupt lines at the end of the
   second-to-last cycle", and otherwise one instruction later (plan 12, decision 2).
5. A frame ends when the PPU wraps to dot 0 of scanline 0; `Console#run_frame` steps until the PPU's frame number
   changes, so it stops within the first instruction of the next frame (plan 12, decision 7).

6. The APU is caught up the same way (plan 22, decision 3): `Apu#catch_up(cpu_cycle)` runs every CPU cycle before
   `cpu_cycle`, the frame counter and the triangle timer on each, the pulse, noise and DMC timers on the even ones;
   `Console#step` calls it after the PPU, and an APU register access first catches it up through the access cycle
   (`Cpu#access_cycle`, `cycles - 1`), the APU taking the CPU as its clock.

7. **Sync deadline** (plan 28, decisions 1-3). Between register accesses the PPU reaches the CPU only through /NMI,
   the end of the frame and the board's IRQ. `Ppu#sync_cycle` is the first CPU cycle at whose end the PPU must be
   caught up for the CPU to see them on time. It is the earlier of two cycles:
   - the cycle of the frame timing's next event, `(elapsed dots + FrameTiming#dots_to_next_event) / 3`, where the
     event is VBlank's start or end, or the next frame's first dot with the odd frame's skipped dot;
   - the board's `earliest_irq_cycle`. For MMC3 it is `cycle + (clocks to the IRQ − 1) × 3`, because counted A12 rises
     are at least 3 M2 cycles apart.

   An event on dot D changes /NMI on cycle (D + 1) / 3, which a step polls only if it starts after it, so D / 3 needs
   no margin. `run_frame` catches the PPU up to a step's end when the step reached that cycle, or when a register
   access within the step brought the PPU into the next frame. The cycle is memoised and cleared by every catch-up,
   register access and reset: every write that could move it is preceded by a catch-up. `Console#step` keeps catching
   up after every step, so the tracer reads the PPU's position after each instruction.

8. **The APU's sync deadline** (plan 29, decisions 4-6). Between register accesses the APU reaches the CPU only
   through its interrupt flags and the DMC's fetches, which halt the CPU. `Apu#sync_cycle` is one past the earlier of:
   - `FrameCounter#next_interrupt_cycle`: the tick that reaches mode 0's next interrupt step unless inhibited, or
     sooner the tick a pending `$4017` write takes effect on;
   - `Dmc#next_fetch_cycle`: the get cycle of the timer clock that starts the output unit's next output cycle, while
     bytes remain; it also bounds the DMC's interrupt, set on the fetch of the last byte.

   An event on cycle F happened in the catch-up after the step that crosses F, so F + 1 keeps it there, with the same
   IRQ stamp and the same stall. `run_frame` catches the APU up from that cycle on and once more after its loop, to
   the last step's end, so the frame's audio is complete: not past a DMC stall its own catch-up added, which `step`
   too leaves to the next step's catch-up. `Console#step` still catches it up after every step. The cycle is memoised and
   cleared by every catch-up, register write and reset.

**Relation to the [Catch-up](https://www.nesdev.org/wiki/Catch-up) page.** The page's recipe is to find the next
time one component could affect another (for example the CPU writing to a PPU register), run the least predictable
component (the CPU) up to that time, then run the others up to it. The PPU registers are such sync points now; the
mapper registers are too since plan 21 (decision 6): the base asks `PpuRegisterSync#catch_up` before handing a write
to `$8000-$FFFF` to its board, so a bank switch or an MMC3 IRQ acknowledge lands on its dot. The APU registers are
since plan 22. Plan 28 adds the recipe's other half: the CPU runs ahead of the PPU up to the next cycle the PPU could
affect it on (step 7), and plan 29 the same for the APU (step 8).

### Interrupt timing

Plan 22 (decision 1), from [CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts). `Cpu::InterruptLines` is the
arbiter of `Cpu::NmiDetector` (the edge, plan 12) and `Cpu::IrqLine` (the wired-OR level, each assert and release
stamped with its cycle). A step starting on `cycle` polls what came before `cycle - 1`, the previous instruction's
second-to-last cycle, with these exceptions, each told to the lines by the CPU and used by the next poll only:

- `CLI`, `SEI` and `PLP` "change the I flag after polling for interrupts": the poll sees the I from before them.
- A taken branch that does not cross a page polls one cycle earlier ("not before the third CPU cycle").
- A DMA halts the CPU after the instruction polled, and a halted CPU polls nothing: the poll looks back past the
  stall (decision 9, calibrated with `cpu_interrupts_v2/4-irq_and_dma`).
- "The interrupt sequences themselves do not perform interrupt polling": after BRK, an IRQ or an NMI, the handler's
  first instruction runs before another interrupt.
- BRK and the interrupt sequence pick their vector after tick 4: the CPU asks its interrupt sync (the console's
  `PpuRegisterSync`) to catch the PPU up, and an NMI edge by then hijacks them to `$FFFA`.

An IRQ released on or after the poll cycle (a `$4015` read or `$E000` write on an instruction's last cycle) is still
taken once.

**Why not instruction-level catch-up any more.** With the PPU synchronised only after each instruction, a CPU write
reached it early and a read saw stale state; `ppu_vbl_nmi/04-nmi_control` ("Immediate occurence should be after NEXT
instruction") cannot pass that way, since `STA $2000` writes on its last cycle, after the CPU polled.

**Cost.** One `catch_up` call per PPU register access, and in `run_frame` a few per frame: three with rendering
disabled and no board IRQ. Each call runs ranges of dots, one per scanline or less. Plan 25 measured the loop around
each dot at about a quarter of a Super Mario Bros. 3 frame. Plan 28's deadline, ranges and whole tiles took that frame
from 44.5 to 35.9 ms under YJIT (interleaved A/B), with identical frame and audio digests
([benchmarks](benchmarks.md#plan-28-ranges-of-dots-2026-11-22)). The APU, caught up after every step until plan 29, is
caught up about 30 times a frame, by runs; plan 29 took the frame from about 35 to about 29 ms under YJIT
([benchmarks](benchmarks.md#plan-29-the-apus-sync-deadline-and-runs-2026-11-23)).

**Upgrade path:** tick on every bus access — advance the PPU and APU on every CPU read and write. Exact, with the
most calls.

## Layout and loading

| Path | Constant | Contents |
|---|---|---|
| `lib/ruby/nes.rb` | `Ruby::Nes` | entry point: `require_relative` of every component, in dependency order |
| `lib/ruby/nes/console.rb` | `Ruby::Nes::Console` | wires components, power-up and reset, runs the clock (`step`, `run_frame`) |
| `lib/ruby/nes/console/` | `Ruby::Nes::Console::PpuRegisterSync` | the `ppu_registers:` device that catches the PPU up before each register access |
| `lib/ruby/nes/cartridge.rb` | `Ruby::Nes::Cartridge` | the loaded cartridge (header, PRG, CHR) |
| `lib/ruby/nes/cartridge/` | `Ruby::Nes::Cartridge::Header`, `::Loader`, errors | iNES parsing |
| `lib/ruby/nes/mappers.rb` | `Ruby::Nes::Mappers` | `Mappers.build` factory |
| `lib/ruby/nes/mappers/` | `Ruby::Nes::Mappers::BankWindows`, `::Base`, `::Nrom`, `::Uxrom`, `::Cnrom`, `::Axrom`, `::Mmc1`, `::Mmc3` | the windows a board shows a memory through, the board base, then one file per mapper |
| `lib/ruby/nes/mappers/mmc1/` | `Ruby::Nes::Mappers::Mmc1::SerialPort` | MMC1's serial load port |
| `lib/ruby/nes/mappers/mmc3/` | `Ruby::Nes::Mappers::Mmc3::IrqCounter`, `::A12Watcher` | MMC3's scanline counter and the A12 filter that clocks it |
| `lib/ruby/nes/cpu_bus.rb` | `Ruby::Nes::CpuBus` | CPU address decoding, RAM, open bus |
| `lib/ruby/nes/cpu_bus/` | `Ruby::Nes::CpuBus::Disconnected`, `::OamDma` | the device in an empty slot; the OAM DMA unit the bus owns |
| `lib/ruby/nes/cpu.rb` | `Ruby::Nes::Cpu` | registers, operand fetch, `step`, interrupts |
| `lib/ruby/nes/cpu/` | `Ruby::Nes::Cpu::Status`, `::Stack`, `::Shifter`, `::AddressingModes`, `::Dispatch`, `::Opcodes`, `::Interrupts`, `::InterruptLines`, `::NmiDetector`, `::IrqLine` | status flags, stack, the shift/rotate unit, addressing modes, the opcode dispatch and reset/NMI/IRQ (mixins of `Cpu`), the opcode table of all 256 opcodes (mnemonic, mode, base cycles, official or not), the interrupt poll's arbiter, the NMI edge detector and the IRQ wired-OR level |
| `lib/ruby/nes/cpu/instructions/` | `Ruby::Nes::Cpu::Instructions::LoadStore`, `::Arithmetic`, `::Branches`…, `::ReadModifyWriteCombos`, `::ImmediateCombos`, `::Unstable` | one mixin of `Cpu` per instruction group, each instruction a method taking the resolved effective address; the last three hold unofficial opcodes only (plan 09) |
| `lib/ruby/nes/ppu_bus.rb` | `Ruby::Nes::PpuBus` | PPU address decoding |
| `lib/ruby/nes/ppu_bus/` | `Ruby::Nes::PpuBus::Nametables`, `::PaletteRam` | VRAM through the mirroring, palette RAM |
| `lib/ruby/nes/ppu.rb` | `Ruby::Nes::Ppu` | the register decoder, the PPU's I/O latch, the catch-up to a CPU cycle, reset and the writes it ignores; the PPUCTRL and PPUMASK settings told to the renderer |
| `lib/ruby/nes/ppu/` | `Ruby::Nes::Ppu::ScrollRegisters`, `::Oam`, `::DataPort`, `::FrameTiming`, `::DotClock`, `::VerticalBlank`, `::Renderer`, `::RenderSchedule`, `::BackgroundFetcher`, `::LayerVisibility`, `::PixelComposer`, `::Picture`, `::SpriteRenderer`, `::SpriteEvaluation`, `::SpriteRows`, `::OverflowSearch`, `::SecondaryOam`, `::SpriteFetcher`, `::SpritePatternAddress` (`::EightByEight`, `::EightBySixteen`), `::SpriteLine`, `::PriorityMultiplexer`, `::SpriteZeroHit`, `::SpriteStatus` | v/t/x/w, OAM and OAMADDR, PPUDATA, the dot/scanline/frame counters with the odd-frame skip and the `$2002` read race, the elapsed dots, the VBlank flag and /NMI output; the background and sprite pipelines and the frame buffer (see Rendering) |
| `lib/ruby/nes/apu.rb` | `Ruby::Nes::Apu` | the APU's register decoder (a channel table), `$4015`, the catch-up to a CPU cycle, the mixed output, power-up and reset |
| `lib/ruby/nes/apu/` | `Ruby::Nes::Apu::Pulse`, `::Triangle`, `::Noise`, `::Dmc`, `::Timer`, `::DutySequencer`, `::Envelope`, `::Sweep`, `::LengthCounter`, `::LinearCounter`, `::TriangleSequencer`, `::NoiseShiftRegister`, `::FrameCounter`, `::InterruptFlag`, `::Mixer`, `::GetCycles`, `::FastChannels` | the five channels and their units, the frame counter, the interrupt flags of the frame counter and the DMC, the mixer (plans 22 and 23), the get cycles the runs count in (plan 29), and the triangle and the noise clock by clock through a run (plan 33) |
| `lib/ruby/nes/apu/dmc/` | `Ruby::Nes::Apu::Dmc::Sample`, `::MemoryReader`, `::OutputUnit` | the DMC's address and bytes-remaining counters, its sample buffer filled by DMA, and its output level (plan 23) |
| `lib/ruby/nes/input/` | `Ruby::Nes::Input::Controller`, `::ControllerPorts` | a standard controller; the device answering `$4016`/`$4017` |
| `lib/ruby/nes/audio.rb` | `Ruby::Nes::Audio` | the sample rate and the RC time constant (plan 24) |
| `lib/ruby/nes/audio/` | `Ruby::Nes::Audio::Resampler`, `::OutputStage`, `::HighPassFilter`, `::LowPassFilter`, `::SampleBuffer` | the box resampler, the NES's output filters and 16-bit conversion, the frame's samples (plan 24) |
| `lib/ruby/nes/frontends/` | `Ruby::Nes::Frontends::Base`, `::Driver` (`::Driver::NoFrameObserver`, `::Driver::NoStates`), `::Headless`, `::InputScript`, `::Palette`, `::Png`, `::Screenshot`, `::Wav`, `::Controls`, `::Gamepad`, `::Players`, `::StickDirections`, `::Raylib`, `::RaylibInput`, `::RaylibLibrary`, `::RaylibAudioStream`, `::AudioDeviceLatency`, `::RaylibPicture`, `::Viewport`, `::KeyConfig` (`::KeyConfig::Section`), `::KeyBindings`, `::Hotkeys`, `::OppositeDirections`, `::FramePacing`, `::AudioPacing`, `::FrameRate`, `::MonotonicClock`, `::Notice` | the frontend contract and its loop, the headless frontend and its input script, RGB conversion, PNG encoding (plan 16); keys to controller buttons and the raylib window (plan 17), the frame on the GPU (plan 32); the window's viewport, key config, hotkeys, direction filter, pacing and frame rate (plan 18); WAV encoding, the raylib audio stream and audio-driven pacing (plan 24), the audio device's latency (plan 39); gamepads, both players and the raylib input (plan 36); a frame as a PNG image and the window's messages (plan 35). Never loaded by `lib/ruby/nes.rb` |
| `lib/ruby/nes/frontends/browser.rb`, `frontends/browser/` | `Ruby::Nes::Frontends::Browser::PixelFont`, `::RomName`, `::Rom`, `::RomList`, `::ButtonPresses`, `::Cursor`, `::MotionWatch`, `::PreviewCache`, `::Preview`, `::Screen`, `::Menu`, `::EmptyMenu` | the ROM browser's screen (plan 37): the ROMs of a folder, their names and marks, navigation from controller 1, the preview of the game in focus from a cached save state, and the menu composed as an NES frame with an 8 × 8 font of its own. Loadable without raylib; never loaded by `lib/ruby/nes.rb` |
| `lib/ruby/nes/debug/` | `Ruby::Nes::Debug::Tracer` | tooling off the hot path |
| `lib/ruby/nes/bits.rb` | `Ruby::Nes::Bits` | the bit constants hot paths use inline (`BYTE_MASK`, `PAGE_MASK`…) and readable bit helpers for code off the hot path |
| `lib/ruby/nes/command_line.rb`, `command_line/` | `Ruby::Nes::CommandLine`, `::Options`, `::Jit`, `::ConfigFile`, `::Window`, `::RaylibWindow`, `::Game`, `::Browser` | `exe/ruby-nes`: loads the core and the frontends, parses the arguments, enables the JIT, runs a ROM headless or in the window (plans 16 and 18); a game in an open window and the ROM browser's loop (plan 37) |
| `lib/ruby/nes/saves.rb`, `saves/` | `Ruby::Nes::Saves`, `::Directory`, `::AtomicFile`, `::BatteryFile`, `::BatteryKeeper`, `::NoBattery`, `::Shape`, `::ConstantsDigest`, `::ConsoleState`, `::StateFiles`, `::StateSlots`, errors | the window's battery saves (plan 34): where they live, the `.sav` file, the keeper that loads the save and writes the RAM back; save states (plan 35): the console's shape, a state's bytes and their checks, the slots' files and the player's actions; atomic writes for both. Never loaded by `lib/ruby/nes.rb` |
| `spec/support/test_roms.rb`, `spec/support/test_roms/` | `TestRoms`, `TestRoms::Manifest`, `::Fetcher`… | test ROM harness (plan 02): test tooling, not shipped in the gem |
| `spec/support/blargg.rb`, `spec/support/blargg/` | `Blargg`, `Blargg::Report`, `::LegacyReport`, `::ScreenReport`, `::Runner`, `::Programs` | blargg's "Output at $6000" protocol, the 2005 ROMs' result at `$F8` (plan 14), the older shell's result line on screen (plan 19), and a runner that presses reset when asked (plan 12): test tooling, also used by `rake blargg:run`; specs in `spec/blargg/`, the real ROMs tagged `slow: true` |
| `spec/support/nestest.rb`, `spec/support/nestest/` | `Nestest`, `Nestest::Log`, `::Runner`, `::Divergence` | nestest in automation mode compared with its reference trace (plan 08): test tooling, also used by `rake nestest:diff` |
| `bench/cpu.rb`, `bench/cpu_benchmark.rb`, `bench/cpu_benchmark/` | `CpuBenchmark`, `CpuBenchmark::Workload`, `::Session`, `::Measurement`, `::Report`… | the CPU benchmark (plan 10): nestest looped under no JIT, YJIT or ZJIT, run by `rake bench:cpu` and `rake bench:variants`; specs in `spec/cpu_benchmark/` |
| `bench/frontends.rb`, `bench/frontend_benchmark.rb`, `bench/frontend_benchmark/` | `FrontendBenchmark`, `FrontendBenchmark::Probe`, `::Summary`, `::SquareWave`, `::Backends`, `::Unpaced`, `::Options`, `::CommandLine` | the windowed backend benchmark (plan 17): a ROM in a backend, each present and frame timed, a test tone pushed; run by `rake bench:frontends`; specs in `spec/frontend_benchmark/` |
| `bench/cpu_benchmark/variants/` | — | hot-path experiments that reopen core classes, each loaded only inside a benchmark process of its own (plan 10, decision 3) |
| `bench/frame.rb`, `bench/frame_benchmark.rb`, `bench/frame_benchmark/` | `FrameBenchmark`, `FrameBenchmark::Workload`, `::Session`, `::Measurement`, `::Report`… | the frame benchmark (plan 25): Super Mario Bros. 3 with audio under no JIT, YJIT or ZJIT, run by `rake bench:frames`; specs in `spec/frame_benchmark/` |
| `spinel/cpu.rb`, `spinel/frames.rb` | — | the CPU and the frame benchmarks as plain programs that both CRuby and the Spinel AOT compiler run, with no `OptionParser` (plan 26); measured by `rake bench:spinel`; specs in `spec/spinel/` |
| `spinel/sig/` | — | RBS type seeds Spinel reads with `--rbs`, never CRuby (plan 26, decision 7) |
| `rakelib/spinel.rake` | — | `rake spinel:fetch`: the pinned Spinel release, built under `tmp/spinel` (plan 26) |

Rules:

- **The path follows the constant.** A class or module `X` lives in `x.rb`; constants nested in it live in `x/`
  (`Ruby::Nes::Cartridge::Header` → `lib/ruby/nes/cartridge/header.rb`). A module that is only a namespace (no
  behaviour of its own, like `Input`) has no file: its nested files open it.
- The buses are top-level (`CpuBus`, `PpuBus`), not nested in `Cpu`/`Ppu`: a bus connects devices and belongs to
  none of them (plan 04 builds `CpuBus` before `Cpu` exists).
- **Explicit `require_relative`, no autoloader.** Load order stays visible and nothing depends on `const_missing`,
  which keeps the code friendly to an AOT compiler (plan 26).
- No empty namespaces ahead of time: a plan creates a file together with its first behaviour. `Bits` is created by
  the first plan that needs a helper off the hot path.

## Hot paths

A **hot path** is everything called, directly or indirectly, per CPU instruction, per CPU bus access, per PPU dot or
per APU tick: `Cpu#step` and the instruction implementations, `CpuBus` and `PpuBus` reads and writes, mapper
`cpu_read`/`cpu_write`/`ppu_read`/`ppu_write`, the PPU dot and the APU tick, run or skipped in runs of quiet cycles
(with audio on, `Audio::Resampler#add` or `#add_run`, a float addition per CPU cycle, and once per sample the output
stage and the sample buffer), and the `Console` loop around them.
Loading a ROM, the command line, frontends (they run once per frame), debug tooling and specs are not hot paths.

Rules on hot paths:

- Integers only. Wrap explicitly with named masks (`value & BYTE_MASK`), never rely on overflow.
- Preallocated buffers (RAM, VRAM, OAM, frame buffer) created once; no allocation per cycle or per instruction (no
  temporary arrays, strings, hashes, ranges or blocks that capture new objects).
- No `define_method`, `method_missing`, `send` or `instance_variable_get`: plain methods and constant tables, so
  YJIT/ZJIT can compile them and Spinel can infer their types.
- No exceptions for control flow.
- `Data.define` value objects are fine for configuration (the iNES header), never per cycle.
- Memory is an `Array` of Integer (decision 2): plan 10 measured `String` and `IO::Buffer` slower under the default
  JIT and without one.
- No shift by a varying amount: YJIT compiles `Integer#>>` and `#<<` inline only for an amount it has seen, and a
  varying one (fine X, a quadrant) becomes a method call. A multiplication by a power of two from a table, then a
  constant shift, replaces it (plan 30, decisions 7 and 8). Packed values stay below 62 bits, a Fixnum.

## Readability

The code mirrors hardware but must read like prose to someone who does not know the NES by heart. The rules apply to
production code and specs alike.

- No single-letter or meaningless names (`a`, `x`, `tmp`, `val`), block parameters and loop indices included
  (`accumulator`, `index_x`, not `a`, `x`).
- No abbreviations or acronyms in names — with **exception 1** below.
- Prefer named methods to operator-like ones when Ruby offers them: `first.intersection(second)` over
  `first & second`; `union`, `difference`.
- **Flag tests use `anybits?`, `allbits?` or `nobits?` off hot paths** (`status.anybits?(CARRY_FLAG)`,
  `value.anybits?(SIGN_BIT)`). On hot paths they are inline, `(steps & FLAG) != 0 # glossary: flag-set` (exception 2,
  decision 72): the JITs compile the operators inline but call `anybits?`.
- Masks, flags, addresses and other magic numbers are named constants, citing the NESdev page they come from.
- Off hot paths, other bit arithmetic goes through the intention-revealing helpers of `Ruby::Nes::Bits`
  (`Bits.wrap_to_byte(value)`, `Bits.high_byte(address)`) — with **exception 2** below for hot paths.
- Small methods with intention-revealing names over comments that explain what a block does.

**Exception 1 — hardware acronyms** (decision 4). Documented hardware names are kept in class and constant names
(`Cpu`, `Ppu`, `Apu`, `Oam`, `Dmc`, `PPUCTRL`) because they are what the reference documentation uses and what a reader
searches for. Each is expanded in [`GLOSSARY.md`](GLOSSARY.md#hardware-terms), and the class or constant comment
expands its own. Standard computing acronyms used by the tooling (URL, HTTP, YAML, SHA-256, SSL, JSON, PNG, RGB, CRC,
and the JIT names JIT, YJIT, ZJIT) are allowed on the same terms (decision 5): each is expanded in
[`GLOSSARY.md`](GLOSSARY.md#computing-terms). Anything else is spelled out.

**Exception 2 — inline bit operations on hot paths** (decisions 3 and 72). On hot paths the operators `&`, `|`, `^`,
`~`, `<<`, `>>`, the flag tests (`!= 0`, `== 0` after `&`) and the signed-byte idiom are written inline, so no method
call is paid per cycle, provided that

1. masks and addresses are named constants, and
2. the line ends with a tag naming the readable operation — an anchor in
   [`GLOSSARY.md`](GLOSSARY.md#bit-operations):

```ruby
@accumulator = (@accumulator + operand + carry) & BYTE_MASK # glossary: wrap-to-byte
address = (high << 8) | low # glossary: combine-bytes
```

- A tag names the **intent**, not the expression: `low-byte` and `wrap-to-byte` are the same `& BYTE_MASK`.
- Several operations on one line list them all: `# glossary: high-byte, wrap-to-byte`.
- Inside a tagged idiom, the byte width `8` and the single bit `1` are not magic numbers; every other number is a
  constant.
- A tag does not exempt the line from the 120-column limit (the project's `.rubocop.yml` only exempts lines that are
  entirely a comment).
- `grep -rn 'glossary:' lib` finds every use. A new idiom or acronym gets its glossary entry in the same change.

**Exception 3 — the nibble positions of an unrolled tile** (decision 84). `PixelComposer#draw_tile` and
`#draw_background_tile` unpack 8 pixels of 4 bits, pixel i at bits 31 − 4i to 28 − 4i, by shifts written as the
literals 28, 24, …, 4: the layout is stated in the class comment, and eight constants named after their own value
would add nothing. The masks stay named.

## Known gaps

Hardware behaviour deliberately not modelled yet, each with the plan that revisits it.

| Gap | Hardware | Revisit in |
|---|---|---|
| Dummy reads | The 6502 reads and throws away bytes in several addressing modes ([6502_cpu.txt](https://www.nesdev.org/6502_cpu.txt)). Since plan 12 the indexed modes (absolute,X, absolute,Y, (indirect),Y) make theirs, at the address whose high byte is not fixed yet, on a page cross for reads and always for writes and read-modify-write instructions (`instr_misc/03-dummy_reads` passes, `cpu_dummy_reads` since plan 19 and `instr_misc/04-dummy_reads_apu`, through `$4015`, since plan 22). A read's dummy read reaches the PPU on its own cycle; a write's, and every access of a read-modify-write instruction, reach it on the instruction's last cycle, an approximation of the register sync. The other dummy reads (zero page indexed, implied, the stack) only reach RAM or ROM and are not made, so their open bus effect is missing. | — |
| Interrupt polling point | Modelled since plan 22 (Interrupt timing): the IRQ carries its cycle like the NMI edge, taken branches without a page cross poll one cycle early, DMA stalls and interrupt sequences do not poll; `cpu_interrupts_v2` 1-5 pass. What remains approximate is inside an instruction: read-modify-write instructions on registers, and the dummy reads above. | — |
| IRQ delay after `CLI`, `SEI`, `PLP` | Modelled since plan 22: the poll after them sees the I from before them (`cpu_interrupts_v2/1-cli_latency` passes). | — |
| Interrupt hijacking | Modelled since plan 22: BRK and the interrupt sequence catch the PPU up and pick their vector after tick 4, so an NMI by then sends them through `$FFFA` (`cpu_interrupts_v2` 2 and 3 pass). An IRQ hijacking BRK needs nothing: they share the vector. | — |
| DMC conflict on register reads | A DMC fetch halts the CPU on a read cycle, and the halted 2A03 "repeats the read cycle on which it was halted during every no-operation DMA cycle" ([DMA](https://www.nesdev.org/wiki/DMA)): a `$4016`/`$4017` read then clocks the controller's shift register again, so "the shift register will drop a bit out", "most common symptom of this is spurious Right presses" ([Controller reading](https://www.nesdev.org/wiki/Controller_reading)), and `$2007` and `$2002` see extra reads. The DMC fetches inside the APU catch-up and halts the CPU through `Cpu#halt` (plan 23, decision 1), without repeating the CPU's read; a read clocks the controller once. The expansion port latches (bits 2-1 of a `$4016` write) and third-party controllers that return 0 after the 8th read are not modelled either (plan 15). | A later DMA pass |
| Jammed CPU | The `JAM` opcodes "halt the CPU until reset" ([CPU unofficial opcodes](https://www.nesdev.org/wiki/CPU_unofficial_opcodes)); no reference found says what the bus does meanwhile, how the cycles count, or whether NMI and IRQ act on a jammed CPU. The emulator's choice is a convention: each `Cpu#step` touches no bus, takes no interrupt and returns 2 cycles (`Cpu::JAMMED_STEP_CYCLES`), and the `JAM` opcode itself costs 2. **Technical debt:** search deeper (Visual6502 simulations, "No More Secrets") and replace the convention with a sourced behaviour. | A later CPU pass (no plan yet) |
| Unstable unofficial opcodes | `ANE` (`XAA`), `LAX #imm`, `SHA` (`AHX`), `SHX`, `SHY`, `TAS` and `LAS` depend on the chip, the temperature and the RDY line ("No More Secrets", [csdb.dk/release/?id=198357](https://csdb.dk/release/?id=198357)). The emulator uses the documented formulas without DMA, $EF for `ANE` as the document advises for emulators, and Z and N from the result ([Visual6502 wiki](https://www.nesdev.org/wiki/Visual6502wiki/6502_Opcode_8B_(XAA,_ANE))). `LAX #imm` uses $FF, not the document's $EE: blargg's `instr_test-v5`, whose checksums come from the console, passes only with it, and it also checks `LAX #imm`'s flags, `SHX` and `SHY` (plan 12). `ANE`, `SHA`, `TAS` and `LAS` stay unchecked. | A later CPU pass (no plan yet) |
| PPU I/O latch decay | "At least one bit in this value decays after 3ms to 30ms" ([PPU registers](https://www.nesdev.org/wiki/PPU_registers)). The latch keeps its value forever (plan 12, decision 9): `ppu_open_bus` fails #3, "Decay value should become zero by one second". | A later PPU pass (no plan yet) |
| OAM DMA alignment | Get and put cycles "are aligned to the first and second halves of the APU clock", and "At power-on, whether the first CPU cycle is get or put is random" ([DMA](https://www.nesdev.org/wiki/DMA)). The emulator takes even CPU cycles, counted from `Cpu.new`, as get cycles (a convention; plan 11, decision 3 compares it with Mesen2), so a `$4014` write on an even cycle stalls 513 cycles and on an odd one 514; the APU's `$4017` delay is calibrated against it (plan 22, decision 5, with `cpu_interrupts_v2/4-irq_and_dma`). The copy also happens at once, before the stall, so the PPU sees OAM complete one instruction early. | A later DMA pass |
| VBlank flag at power | "The VBL flag (PPUSTATUS bit 7) is random at power" ([PPU power up state](https://www.nesdev.org/wiki/PPU_power_up_state)). It starts clear, a convention (plan 12, decision 8); reset leaves it as it is, as the hardware does. | — |
| PPU registers ignored at power | The page gives the window of ignored writes to PPUCTRL, PPUMASK, PPUSCROLL and PPUADDR for the reset signal, "set on reset and cleared at the end of VBlank" ([PPU power up state](https://www.nesdev.org/wiki/PPU_power_up_state)). The emulator opens the same window at power-up, since `Console.new` resets the PPU (plan 12, decision 8); a plain `Ppu.new` accepts writes at once, for specs. | — |
| Rendering toggle delay | "Toggling rendering takes effect approximately 3-4 dots after the write" ([PPU frame timing](https://www.nesdev.org/wiki/PPU_frame_timing)). The frame timing sees PPUMASK's rendering bits at once, when it decides the odd-frame skip at dot 339 of the pre-render scanline. `ppu_vbl_nmi/10-even_odd_timing` fails #3, "Clock is skipped too late, relative to enabling BG". | A later PPU pass (no plan yet; plan 13, decision 4) |
| OAMDATA during rendering | OAMDATA writes during rendering "do not modify values in OAM, but do perform a glitchy increment of OAMADDR"; its reads "expose internal OAM accesses during sprite evaluation and loading" ([PPU registers](https://www.nesdev.org/wiki/PPU_registers)). Writes are ignored completely, as the page advises for emulators (plan 14, decision 4); reads return OAM at OAMADDR, as outside rendering. | A later PPU pass (no plan yet) |
| Sprite overflow timing | The flag is set on the dot the evaluation finds the ninth sprite (2 dots per OAM read from dot 65, [PPU sprite evaluation](https://www.nesdev.org/wiki/PPU_sprite_evaluation)). The evaluation runs whole at dot 257 (plan 14, decision 2), so the flag shows up to ~190 dots late: `sprite_overflow_tests/3.Timing` fails #5, "Set too late for first scanline". | A later PPU pass (no plan yet) |
| OAMADDR at the start of evaluation | "The value of OAMADDR at this tick determines the starting address for sprite evaluation for this scanline, which can cause the sprite at OAMADDR to be treated as it was sprite 0"; on the 2C02 a non-zero OAMADDR when rendering starts copies "the eight bytes starting at OAMADDR & 0xF8" over the first eight, and OAMADDR writes "corrupt OAM" ([PPU registers](https://www.nesdev.org/wiki/PPU_registers)). The evaluation always starts at sprite 0 and OAM is never corrupted (plan 14, decision 5). | A later PPU pass (no plan yet) |
| Sprite 0 hit dot | "Sprite 0 hit acts as if the image starts at cycle 2" ([PPU rendering](https://www.nesdev.org/wiki/PPU_rendering)); the flag is set on the dot the pixel is composed, x + 1, one dot earlier (plan 14, decision 9). `sprite_hit_tests_2005.10.05` 09-11 pass with it. | — |
| Background fetches with no visible effect | The nametable fetches of dots 257-320 and the two of 337-340 ("only used by MMC5", [PPU rendering](https://www.nesdev.org/wiki/PPU_rendering)) are not made (plan 13, decision 6); a mapper that counts PPU reads would miss them. MMC3 does not need them: nametable addresses have A12 low, and the lows they would put between sprite fetches are shorter than its filter (plan 21, decision 9). The sprite pattern fetches of 257-320 are made on their dots since plan 14 (decision 3); an empty slot's dummy fetch takes its row from Y `$FF`, where the hardware's first empty slot keeps sprite 63's Y. | MMC5, if ever |
| Byte under a palette read | A PPUDATA read of the palette fills the buffer from "a normal read from PPU memory at the specified address, "underneath" the palette data" ("usually mirrored nametables"). The emulator reads the nametable byte `$1000` below (the `$2F00-$2FFF` mirror), an inference from "$3000-3EFF is usually a mirror of" `$2000-$2EFF`. | When a board maps `$3000-$3FFF` differently |
| MMC3 IRQ timing | The counter is clocked on the dot a pattern fetch with A12 high happens (261 for the first sprite fetch, where NESdev says "PPU cycle 260"), and M2 edges are counted as elapsed dots divided by 3 without their phase. Since plan 22 its IRQ carries the M2 cycle of the clock and is polled at the right point, yet `mmc3_test_2/4-scanline_timing` still fails #2, "Scanline 0 IRQ should occur later when $2000=$08"; SMB3's status bar is still. | A later mapper pass (no plan yet) |
| OAM DMA from a read-modify-write | A read-modify-write instruction on `$4014` writes it twice (decision 48), so the emulator starts OAM DMA twice: two copies of 256 bytes, the second from the modified page, and one stall. NESdev's [DMA](https://www.nesdev.org/wiki/DMA) page does not describe a second `$4014` write during a transfer; the OAM left is the modified page's, as the last copy. | A later DMA pass (no plan yet; plan 23 shares the DMA unit) |
| `$4015` read on the cycle the frame flag is set | The APU page says "If an interrupt flag was set at the same moment of the read, it will read back as 1 but it will not be cleared"; apu_test's `6-irq_flag_timing` (#5, "Flag last set too late"), written against the console, needs the read on the cycle of the last set to clear it. The emulator always clears (plan 22, decision 7); "the same moment" may be a finer timing than a CPU cycle. | — |
| Frame counter at power-up and reset | `apu_reset`'s readme: "At power, it is as if $00 were written to $4017, then a 9-12 clock delay, then execution from address in reset vector", and at reset the last value is written again. The emulator starts mode 0 from cycle 0 when the console is built, and rewrites the value on the cycle the APU stands at when reset is pressed, without that delay; `apu_reset/4017_timing` passes all the same (it prints a delay of 7). | — |
| DMC DMA timing | "Load DMAs take 3 cycles and reload DMAs take 4 unless the halt is delayed by an odd number of cycles"; "DMA can only halt on CPU read cycles", so write cycles delay it "up to 3 cycles"; load DMAs "are scheduled to halt the CPU on a get cycle during the 2nd APU cycle after the write"; "DMC DMA occurring during OAM DMA will cost only 2 cycles" ([DMA](https://www.nesdev.org/wiki/DMA)). The emulator halts 3 cycles for a load and 4 for a reload, fetches the load on the `$4015` write, and adds a DMC halt to OAM DMA's whole (plan 23, decisions 2 and 3). The DMC fetches during the APU catch-up, so a reload's halt lands at the next instruction boundary or register access rather than on its cycle; a register access then catches the APU up past the stall, so its stamp and the APU's state agree, a write included, though the hardware would delay a halt past write cycles. The output unit's state at power is a convention (plan 23, decision 9). `apu_test` 7-8 and `apu_reset/works_immediately` pass. | A later DMA pass |
| IRQ released and re-asserted within a stall | `Cpu::IrqLine` keeps one assert and one release cycle; a poll that looks back past a DMA stall (plan 22, decision 9) misses an IRQ released and asserted again within the stall. OAM DMA's 513 cycles made it possible since plan 22; DMC stalls add 3-4 cycles at a time. No test ROM has needed it (plan 23, decision 7). | When a ROM needs it |
| Noise shift register at power-up | The APU Noise page loads it with 1; CPU power up state gives "$0000 (all 0s, first clock shifts in a 1)". The emulator starts at 1 (plan 23, decision 6): one step apart. | — |
| Ultrasonic triangle | Periods below 2 play at up to 55.9 kHz; the hardware's filter averages them "into constant output at roughly half amplitude" ([APU Triangle](https://www.nesdev.org/wiki/APU_Triangle)). The APU outputs every step (plan 23, decision 4) and the box resampler averages them the same way; SMB3's menu and world map music, heard in plan 24, show no audible noise, so no workaround (plan 24, decision 8). | When a game sounds wrong |
| Low-pass filter near Nyquist | "A first-order low-pass filter at 14 kHz" ([APU Mixer](https://www.nesdev.org/wiki/APU_Mixer)). At 48 kHz the discrete RC form cuts more than the analogue filter near the Nyquist frequency (24 kHz): a 14 kHz sine comes out at 0.55 of its amplitude rather than 1/√2 (measured in plan 24). A bilinear transform with pre-warping would match the cut-off; the difference sits above what the music uses (plan 24). | — |

## Frame buffer contract

- The PPU writes **pixels of 0–511** into preallocated buffers of 256 × 240 entries, row by row: bits 5-0 are the
  palette index (a 6-bit value selects one of the 64 colours, see
  [PPU palettes](https://www.nesdev.org/wiki/PPU_palettes)), bits 8-6 PPUMASK's emphasis bits 7-5 (bit 6 red, bit 7
  green, bit 8 blue on NTSC, [Colour emphasis](https://www.nesdev.org/wiki/Colour_emphasis)), which "are applied
  independently of greyscale" (plan 16, decision 2).
- **Who draws** (plan 30, decision 1): `Ppu::Picture` owns both buffers and the colour of each of the 32 palette
  entries (`colours`, one array rebuilt in place when palette RAM, which tells it of every write, greyscale or emphasis
  change). `Ppu::PixelComposer` holds the picture's `drawn_frame` and `colours` and stores the visible pixels itself;
  `PixelComposer#complete_picture` completes the frame and takes the picture's new `drawn_frame`; it is the only caller
  of `Picture#complete_frame`, or the composer would keep drawing into the published buffer. The picture draws the
  forced blank's pixels.
- **Double buffering** (plan 16, decision 1): `Ppu::Picture` draws into one buffer and, when the PPU enters the
  post-render scanline 240, swaps it with the one `Ppu#frame_buffer` returns. So `Ppu#frame_buffer` is always one
  whole frame, although `Console#run_frame` stops within the first instruction of the next one. The two arrays
  alternate: the one a frontend gets is valid until the next frame completes, then drawn over, so a frontend asks for
  it after each frame and copies it to keep it. Every visible pixel is drawn every frame (rendering or forced
  blank), so nothing stale survives in the back buffer.
- Converting indices to RGB, scaling and presenting are the **frontend's** job. The core never depends on a graphics
  library.

## Concurrency

No threads and no Ractors in the core. CPU, PPU and APU are coupled at cycle granularity, so passing messages between
them would cost more than it saves. Revisit only if profiling finds a separable stage (for example audio
presentation, in a frontend).

## Decisions log

| # | Date | Decision | Reason | Revisit in |
|---|---|---|---|---|
| 1 | 2026-11-17 | Clock model: instruction-level catch-up | Simpler, fewer calls per instruction in Ruby | Superseded by 23 (plan 12) |
| 2 | 2026-11-17 | Memory container: `Array` of Integer | Most readable; plan 10 measured a binary `String` −4% and `IO::Buffer` −24% under YJIT, both slower without a JIT ([benchmarks](benchmarks.md#findings)) | — |
| 3 | 2026-11-17 | Hot paths write bit operations inline with named constants and `# glossary:` tags; flag tests always use `anybits?`/`nobits?` | No method call per cycle, meaning still one lookup away; RuboCop enforces the predicates. Plan 10: `Bits` helpers on the per-instruction path cost nothing measurable under YJIT and ZJIT but 14% without a JIT, and that path is only a lower bound of a full conversion | Flag tests narrowed by 72 (plan 25); the helpers lead closed by plan 25 (a call costs about 5 ns under YJIT) |
| 4 | 2026-11-17 | Hardware acronyms kept in names, expanded in the glossary | They match the reference documentation readers search | — |
| 5 | 2026-11-17 | Standard computing acronyms (URL, HTTP, YAML, SHA-256, SSL; JSON, JIT, YJIT, ZJIT since plan 10; PPM since plan 13, replaced by PNG, RGB and CRC in plan 16) allowed in tooling names, expanded in the glossary | They are what the libraries and protocols call them; spelling them out (`address` for URL) would clash with emulator terms | — |
| 6 | 2026-11-18 | The status register is a `Cpu::Status` object holding one boolean ivar per flag; the byte is composed for pushes and the trace, split by pulls | The object hides the representation, so plan 10 could swap it alone: one ivar per flag measured +5% under YJIT, +7% without a JIT and +5% under ZJIT against one Integer with bit masks (the first representation, 2026-11-18) | Kept by plan 25 |
| 7 | 2026-11-18 | The page-cross cycle of indexed reads is charged by `_for_read` resolvers; write and read-modify-write instructions use the plain ones | Tell, don't ask: no flag to query, no second return value | — |
| 8 | 2026-11-18 | Dummy reads are not modelled (see Known gaps) | They matter only for registers with read side effects and open bus, which need the PPU | Superseded by 26 (plan 12) |
| 9 | 2026-11-18 | Opcode dispatch is a `case` on the opcode's high nibble whose `when`s each hold a `case opcode` of that row, with an integer literal per `when` (`Cpu::Dispatch#execute`), laid out as the opcode matrix; the only method exempt from the size and complexity Metrics cops | `opt_case_dispatch` with no `Proc#call` or `send` per instruction, a shape Spinel can type, the whole opcode map in one place. Two levels since plan 10: one `case` of 256 `when`s is a linear chain of `Integer#===` under ZJIT; the two-level `case` measured +21% under YJIT and +261% under ZJIT (−6% without a JIT), ahead of a table of lambdas under YJIT | Kept by plan 25 |
| 10 | 2026-11-18 | Instructions are spelled-out methods (`load_accumulator`) in one `Cpu` mixin per group; mnemonics are data in `Cpu::Opcodes` | The readability rule against abbreviations; the tracer still finds the mnemonic | — |
| 11 | 2026-11-18 | The read-modify-write double write is not modelled (see Known gaps) | Only devices that react to every write notice it; none exists before MMC1 | Plan 20 |
| 12 | 2026-11-18 | `Cpu.new` takes one optional keyword per register, `stack_pointer:` included; `Metrics/ParameterLists` is disabled on that method alone | The list is as long as the register file; specs declare the state instead of mutating it. The all-zero defaults are the state before the power-up reset sequence: power-up is `Cpu.new` + `Cpu#reset` (plan 07) | — |
| 13 | 2026-11-18 | Interrupt lines are levels set with `Cpu#nmi_line=` and `Cpu#irq_line=`; `Cpu::InterruptLines` detects the NMI's rising edge, keeps it pending until taken, and names the vector to take (NMI first, then IRQ unless the status's I is set); reset discards a pending NMI; the console combines the IRQ sources and sets the line after each catch-up (plan 12 decides). Plan 12: `nmi_line=` became `nmi_line_changed(asserted, cycle)` (decision 24) and the IRQ sources a wired-OR push (decision 25) | On hardware the edge detector is in the CPU, so enabling NMI in PPUCTRL during VBlank needs no special case and several IRQ sources combine with `\|\|`; one object keeps edge, level, masking and priority out of `Cpu#step`. Plan 10: inlining the poll in `Cpu#step` measured 0% to +6% under YJIT across runs, no clear winner | — |
| 14 | 2026-11-18 | An interrupt is a `Cpu#step` of its own: before the opcode fetch, `step` takes the interrupt and returns 7 cycles; reset also costs 7 cycles | Lines raised while the console catches up after an instruction are seen before the next one; the tracer sees an interrupt as one step; reset "goes through the same sequence" | Plan 12 (clock model) |
| 15 | 2026-11-18 | The interrupt polling point, the `CLI`/`SEI`/`PLP` delay and interrupt hijacking are not modelled (see Known gaps) | They depend on timing inside an instruction, which instruction-level catch-up does not have | The NMI polling point is modelled since plan 12 (decision 24); the rest in plan 22, with `cpu_interrupts_v2` |
| 16 | 2026-11-18 | All 256 opcodes have a `Cpu::Opcodes` entry and a dispatch `when`; unofficial entries are marked (`Opcode#official?`) and traced with `*`, as nestest.log marks them; the seven unstable ones follow "No More Secrets" (see Known gaps) | No opcode raises: nestest's full log, `instr_test-v5` and any game that hits an unofficial opcode run on | Plan 12 (`instr_test-v5`) |
| 17 | 2026-11-18 | A `JAM` opcode puts the CPU in a jammed state (`Cpu#jammed?`) that only `Cpu#reset` clears; a jammed step costs 2 cycles and touches nothing (see Known gaps) | The frontend can show the halt, and the console keeps its clock running as the hardware does | When a source for the jammed behaviour is found |
| 18 | 2026-11-18 | Each row's column 2 is its `case`'s `else` (the `JAM` in 12 rows, the opcode `$x2` in rows 8, A, C and E) and row F is the outer `else`; repeated bodies keep one `when` per opcode (`Lint/DuplicateBranch` disabled on the two rows that need it) | A `when` for every value leaves the implicit `else` unreachable, and Ruby's branch coverage counts it; the map stays readable byte by byte | — |
| 19 | 2026-11-18 | YJIT is the project's default JIT | Plan 10: fastest with every variant measured, 16.4 emulated MHz (915% of real time) on nestest against 9.0 for ZJIT and 3.7 without a JIT ([benchmarks](benchmarks.md#findings)) | Plan 25 (whole frames): kept, YJIT 23.4 fps against 15.4 for ZJIT |
| 20 | 2026-11-18 | OAM DMA is `CpuBus::OamDma`, owned by `CpuBus`, which routes `$4014` writes to it; the stall comes back through `CpuBus#take_stall_cycles(halt_cycle)`, added by `Cpu#step` after every step; even CPU cycles are get cycles | The DMA's collaborators are the bus's own (CPU reads, `$2004` writes), so no circular wiring, and the `apu_registers:` and `controller_ports:` slots (decision 35) stay for the APU and the controllers; DMC DMA (plan 23) reports through the same channel. The query per step measured about −8% under YJIT on nestest | Amended by 64 (plan 23: the DMC pushes through `Cpu#halt`); the OAM push model left by plan 25 (decision 9) |
| 21 | 2026-11-18 | The PPU's I/O latch is modelled without decay; `Ppu#cpu_read` ignores the CPU data bus | Write-only registers and PPUSTATUS's bits 4-0 answer it; decay needs time (Known gaps). Plan 12 kept it without decay (decision 9) | A later PPU pass |
| 22 | 2026-11-18 | `PpuBus::Nametables` asks the mapper's `mirroring` on every access and maps it through a constant table; 4 KiB of VRAM support four-screen | MMC1, MMC3 and AxROM change the mirroring at runtime; four-screen costs one table row | Pushed by the board since plan 30 (decision 86) |
| 23 | 2026-11-19 | Clock model: register-access catch-up. `Cpu#step` charges the base cycles before running the instruction; `Console::PpuRegisterSync` catches the PPU up to `cycles - 1` before every `$2000-$3FFF` access, and `Console#step` to `cycles` after the step | `ppu_vbl_nmi/04-nmi_control` cannot pass with instruction-level catch-up; one call per register access and one per step | Mapper registers synchronised since plan 21 (decision 53); plan 22 (APU registers); `run_frame` catches up only from the PPU's sync cycle on since plan 28 (decision 74) |
| 24 | 2026-11-19 | The NMI edge carries the first CPU cycle whose φ2 sample sees it (`Cpu#nmi_line_changed(asserted, cycle)`, the PPU stamping `(dot + 1) / 3`); a release within that same cycle cancels it; `InterruptLines#acknowledge(cycle)` takes it only when it came before the previous instruction's last cycle | The edge detector "polls the status of the NMI line during φ2 of each CPU cycle", and "the status of the interrupt lines at the end of the second-to-last cycle" is what the poll sees. The φ2 point is calibrated with `ppu_vbl_nmi` 05-08, which pass only with it (not with the change counted on its own dot's cycle, nor two dots ahead) | — |
| 25 | 2026-11-19 | IRQ sources combine as a wired-OR push: each asserts and releases its own bit on a shared line, replacing the mappers' `irq?` | The hardware's open-collector line; no query per instruction (a similar per-step query cost about 8% under YJIT) | Implemented by decision 51 (plan 21) |
| 26 | 2026-11-19 | The indexed addressing modes make their dummy read (`_for_read` resolvers on a page cross, the plain ones always) | `instr_misc/03-dummy_reads` checks them through `$2002`'s side effect; about 2% under YJIT on nestest ([benchmarks](benchmarks.md)) | Kept by plan 25 |
| 27 | 2026-11-19 | Power-up is `Console.new`: the CPU's and the PPU's reset, then the PPU catches up the reset's 7 cycles; `Ppu.new` accepts writes at once, `Ppu#reset` opens the window of ignored writes until VBlank ends | nestest.log's `PPU:  0, 21` at `CYC:7`; specs of single PPU registers stay simple | — |
| 28 | 2026-11-19 | Test ROM runs are examples tagged `slow: true`, run only with `SLOW=1`; CI runs them in a job of its own under YJIT on every push and pull request, and `implement-plan` phase 5 runs `SLOW=1 bundle exec rake` for CPU, PPU, console and mapper plans | Each ROM runs seconds of emulated time; the default suite stays fast | — |
| 29 | 2026-11-19 | `LAX #imm` ORs $FF into A (A and X get the operand), not "No More Secrets"' $EE | blargg's `instr_test-v5/03-immediate`, whose checksum comes from the console, passes only with $FF | — |
| 30 | 2026-11-19 | The background is rendered per dot: `Ppu::BackgroundSchedule` maps each dot to step flags from constant tables, `Ppu::BackgroundRenderer` runs them on the fetcher, shifters, scroll registers, visibility and picture | Mid-scanline register writes (SMB3's status bar) land on the right dot; tables, not nested conditions, carry the NESdev timing (plan 13, decision 1) | Composition folded in by 73 (plan 25); ranges of dots and whole tiles since plan 28 (decisions 75 and 76) |
| 31 | 2026-11-19 | A PPUDATA access during rendering increments coarse X and Y instead of adding 1 or 32; `Ppu::DataPort` asks `FrameTiming#rendering_in_progress?` on each access | "During rendering [...] triggering a coarse X increment and a Y increment simultaneously" ([PPU scrolling](https://www.nesdev.org/wiki/PPU_scrolling)); the frame timing knows the scanline and the rendering flags (plan 13, decision 7) | — |
| 32 | 2026-11-19 | Sprites are evaluated once per visible scanline at dot 257 and composed through a 256-entry line buffer filled front to back at the sprite fetches (dots 261 + 8k and 263 + 8k); the overflow search follows the hardware's diagonal scan | OAMDATA writes are ignored during rendering, so OAM cannot change mid-evaluation; one lookup per pixel; NESdev's "buffer" model of priority; the fetches on their dots feed MMC3's A12 (plan 14, decisions 1-3 and 6) | A later PPU pass (overflow timing, Known gaps) |
| 33 | 2026-11-19 | `BackgroundSchedule`, `BackgroundRenderer` and `BackgroundVisibility` became `RenderSchedule`, `Renderer` and `LayerVisibility`; the sprite steps go to `SpriteRenderer`, the sprite pattern address is a strategy per sprite size, and sprite 0 hit is its own `SpriteZeroHit` | One visibility rule serves both layers; each unit decides one thing (plan 14, decision 7) | — |
| 34 | 2026-11-19 | Composing the sprites costs about 28% of the frame rate under YJIT on nestest (26.6 to 19.2 frames per second, 300 frames after 30) | Three calls per pixel more (sprite pixel, its visibility, the multiplexer) and the sprite steps of dots 257-320 | Superseded by 73 (plan 25) |
| 35 | 2026-11-19 | `CpuBus` splits `$4000-$4017` into an `apu_registers:` slot (`$4000-$4015`, writes to `$4017`) and a `controller_ports:` slot (reads of `$4016`/`$4017`, writes to `$4016`), as it already routed `$4014` writes to the OAM DMA | It mirrors the 2A03, which decodes the range itself (the ports leave the chip through /OE1, /OE2 and OUT0-2); `$4016`/`$4017` are the last two addresses before `$4018`, so a read costs one more comparison and no intermediate device (plan 15, decision 1) | Plan 22 |
| 36 | 2026-11-19 | `Ppu::Picture` double-buffers the frame and swaps at the post-render scanline (`FrameTiming` tells `picture_completed`); `Ppu#frame_buffer` is the last complete frame | A frontend gets one whole frame although `run_frame` stops inside the next one; O(1), no allocation, one comparison per scanline; moving `run_frame`'s stop point would change plan 12's decision 7 (plan 16, decision 1) | — |
| 37 | 2026-11-19 | A pixel is 9 bits: the colour plus PPUMASK's emphasis bits in bits 6-8, ORed by `Ppu::Picture` | Mid-frame PPUMASK writes affect only the following pixels and the frontend never asks the PPU; one OR per pixel (plan 16, decision 2) | Kept by plan 25 |
| 38 | 2026-11-19 | Frontends live in `Ruby::Nes::Frontends` (`Base` contract, `Driver` loop), never loaded by the core; RGB is 3 bytes per pixel built with one `values_at` + `join` over a 512-entry table | The core never depends on a frontend; the join measured 2.8 ms per frame with and without a JIT, ahead of a preallocated `String` (2.4 ms under YJIT, 5.4 ms without one) and `flat_map` + `pack` (12-13 ms) (plan 16, decision 4) | Plan 17 (RGBA if a backend needs it); kept by plan 25 (plan 16 measured the alternatives) |
| 39 | 2026-11-19 | The command line is `Ruby::Nes::CommandLine`; `Debug::FrameDump` (PPM) and `rake debug:frame` are replaced by `exe/ruby-nes ROM --headless --screenshot FRAME:PATH` | One image path (PNG through the shared palette) instead of two; "CLI" would be an acronym outside the glossary (plan 16, decisions 5 and 7) | — |
| 40 | 2026-11-19 | The windowed backend is raylib, through `raylib-bindings` in an optional `frontends` Gemfile group; `Frontends::Keyboard` maps library key codes to controller buttons | It tied SDL3 on present cost (~3 ms, nearly all RGB conversion), frame time under every JIT, input and code size, and installs with `bundle install` alone on macOS, Linux and Windows, where SDL3 needs a system package per OS (none on Ubuntu before 26.04); its fixed audio sub-buffers are workable for plan 24 ([backend comparison](backend-comparison.md); plan 17) | Plan 24 (audio sync) |
| 41 | 2026-11-20 | Timer pacing is `Frontends::FramePacing`, injected into the window and called after each present: deadlines a period (1 / 60.0988 s) apart, a frame late by a period or more restarts the schedule | No drift from oversleeping, no catch-up burst when the emulator is slower than real time; plan 24 swaps in audio-driven pacing through the same `wait` (plan 18) | Plan 24 |
| 42 | 2026-11-20 | Pause and reset go through the driver contract (`Frontends::Base#paused?`, `#reset_requested?`); a paused frontend gets the last completed frame again | A frontend never holds the console; the window keeps drawing, reading keys and pacing while paused (plan 18, decision 5) | — |
| 43 | 2026-11-20 | The command line enables the JIT at runtime (`--jit=none\|yjit\|zjit`, YJIT by default); a JIT that cannot be honoured (missing, another already running, `none` with one running) is an error | Ruby 4.0.9 enables YJIT and ZJIT at runtime without a flag but runs one at a time and turns none off; the run never silently differs from what was asked (plan 18, decisions 1 and 8) | Kept by plan 25 |
| 44 | 2026-11-20 | Opposite directions held on the keyboard cancel each other in the window (`Frontends::OppositeDirections`) | NESdev documents no behaviour to emulate; the simplest stateless rule (plan 18, decision 3) | — |
| 45 | 2026-11-20 | Keys come from `~/.config/ruby-nes/config.yml` (`keys:` section, actions to raylib key names, defaults for the rest, one action per key); a key the file gives to an action is taken from the default of any other, and actions left without a key are named at start; window options are command-line flags | The parser needs no gem (key codes injected); a key bound twice would silently lose one action in `Frontends::Keyboard`'s map; moving one action must not force rebinding another (plan 18, decision 7) | — |
| 46 | 2026-11-20 | Every board is a `Mappers::Base`: PRG ROM through two 16 KiB windows, CHR through one 8 KiB window, a board turning register writes into window offsets, banks wrapped by the memory size when the register is written | One read path for every board, the shape MMC1 uses as is and MMC3 refines, as Mesen2's `BaseMapper`; measured against NROM's single mask with `rake bench:cpu` (plan 19, decision 1; [benchmarks](benchmarks.md)) | Refined by decision 52 (plan 21); kept by plan 25 |
| 47 | 2026-11-20 | Bus conflicts are emulated on CNROM only; NES 2.0 submappers are not read | The NESdev pages for iNES 1.0: "Emulator implementations of iNES mapper 2 [...] without bus conflicts", AxROM's submapper 0 "emulators shouldn't", CNROM's only exceptions are mapper hacks (plan 19, decision 2) | When the header reads NES 2.0 submappers |
| 48 | 2026-11-20 | Read-modify-write instructions on memory write the original byte, then the modified one (`Cpu#write_modified`), the official six and the unofficial combos alike; every device sees both writes | "first [write] the original value back to memory" (Instruction reference), "write unmodified data, then modified" (6502_cpu.txt); the MMC1 serial port reacts to both writes, PPUDATA advances its address twice, OAMDMA starts twice (Known gaps). Replaces plan 06, decision 5 (plan 20, decision 3) | — |
| 49 | 2026-11-20 | Boards get the CPU as their clock (`cpu=`, wired by `Console`); MMC1 ignores a serial port write less than 2 cycles after the previous write unless it is a reset | No device interface changes; both writes of a read-modify-write see the same `Cpu#cycles`, since a step charges its cycles first, and a per-access model would make them 1 apart: under 2 either way, as Mesen2's `MMC1.h` (plan 20, decisions 1 and 2) | — (MMC3 takes the CPU as its IRQ line, decision 51) |
| 50 | 2026-11-20 | The base shows CHR through two 4 KiB windows instead of one 8 KiB window | MMC1's 4 KiB CHR mode; frames of a rendering ROM ran about 5% slower under YJIT, nothing measurable without a JIT ([benchmarks](benchmarks.md); plan 20, decision 5) | Plans 21 (1 KiB windows) and 25 |
| 51 | 2026-11-21 | IRQ sources combine as a wired-OR: `Cpu#assert_irq(source)` / `Cpu#release_irq(source)`, one bit per source in `Cpu::InterruptLines` (`MAPPER_IRQ` first); the boards' `irq?` goes away | Implements decision 25 with its first source, MMC3; plans 22 and 23 add the APU's bits (plan 21, decision 5) | Plan 22 (polling point) |
| 52 | 2026-11-21 | The base shows PRG through four 8 KiB windows and CHR through eight 1 KiB windows, kept by `Mappers::BankWindows`; a board selects a bank of any whole number of windows by address and size | MMC3's granularity, every other board's banks a whole number of windows; headless frames of an NROM ROM about 3% slower under YJIT and ZJIT, within the run-to-run variation ([benchmarks](benchmarks.md); plan 21, decision 8) | Kept by plan 25 |
| 53 | 2026-11-21 | The base catches the PPU up (`PpuRegisterSync#catch_up`, `cpu.cycles - 1`) before every write to `$8000-$FFFF` | Mid-frame bank switches and MMC3 IRQ acknowledges land on their dot; only on the write path, which is rare (plan 21, decision 6) | — |
| 54 | 2026-11-21 | MMC3's counter is clocked from A12 as seen in every address that reaches the board: pattern fetches, PPUDATA accesses and v left on the bus by PPUADDR writes and PPUDATA increments outside rendering (`ppu_address`); the filter counts M2 cycles as `Ppu#elapsed_dots / 3` (the board gets the PPU through `ppu=`) | "no matter what caused it", and mmc3_test_2 clocks through `$2006` and `$2007`; during rendering v's bit 12 is fine Y and the board sees every fetch, so v is not shown then, against the page's "regardless of whether PPU is/is not rendering" (plan 21, decision 10). The watch costs within noise under YJIT and 3-5% under ZJIT on SMB3 frames ([benchmarks](benchmarks.md); plan 21, decisions 1 and 2) | Each fetch's dot inside a range comes from the dot clock since plan 28 (decision 75) |
| 55 | 2026-11-21 | MMC3 follows the Sharp MMC3B/C "new" IRQ behaviour (an IRQ on every clock while the latch is 0), ignores `$A001` and keeps 8 KiB of PRG RAM always enabled | Mapper 4 submapper 0; 5-MMC3 passes, 6-MMC3_alt (the old behaviour) fails as expected; "Many emulators choose not to implement them [...] to avoid an incompatibility with the MMC6" (plan 21, decisions 3 and 4) | NES 2.0 submappers |
| 56 | 2026-11-21 | A header asking for four-screen VRAM makes the base's mirroring `:four_screen`; MMC3 keeps it, boards that control their mirroring (AxROM, MMC1) set theirs over it | iNES flags 6 bit 3 is board-independent; MMC3's `$A000` "has no effect" then; no four-screen AxROM or MMC1 board is known (plan 21, decision 7) | — |
| 57 | 2026-11-21 | The IRQ line carries cycle stamps: `Cpu#assert_irq(source, cycle)` and `#release_irq(source, cycle)`, `Cpu::IrqLine` keeping when it fell and rose; `Cpu::InterruptLines` arbitrates it with `Cpu::NmiDetector` and polls both at the same point, with the exceptions of Interrupt timing (`CLI`/`SEI`/`PLP`, taken branches, DMA stalls, interrupt sequences, hijacking through the console's register sync) | The frame IRQ makes `cpu_interrupts_v2` runnable, and every one of its five singles passes only with these; three units instead of one arbiter whose specification had grown past 30 leaves (plan 22, decisions 1 and 9) | Left by plan 25 (decision 9) |
| 58 | 2026-11-21 | The CPU bus does not store what the `apu_registers:` slot returns | `$4015` "is internal to the CPU and so the external CPU data bus is disconnected when reading it"; the rest of the slot is open bus already, so the assignment moving into each branch costs nothing (plan 22, decision 2) | — |
| 59 | 2026-11-21 | The APU is caught up like the PPU: one CPU cycle at a time, after each step and, before a register access, through the access cycle (`Cpu#access_cycle`); the pulse timers tick on even cycles | `$4015` reads and `$4017` writes land on their cycle; `apu_test` 1-6 pass (plan 22, decision 3) | Left by plan 25 (decision 9) |
| 60 | 2026-11-21 | A `$4017` write takes effect 3 CPU cycles after a write on an odd cycle, 4 after one on an even cycle; OAM DMA keeps even cycles as get cycles | No page says which parity is "during" an APU cycle; `apu_test` passes either way, `cpu_interrupts_v2/4-irq_and_dma` only with this pairing (plan 22, decision 5) | Plan 23 (DMC DMA) |
| 61 | 2026-11-21 | A `$4015` read clears the frame interrupt flag even on the cycle the frame counter set it | `apu_test/6-irq_flag_timing` (#5) needs it, against the APU page's "it will not be cleared" (plan 22, decision 7) | — |
| 62 | 2026-11-21 | The triangle's and the noise's length counters come before their channels (`Apu::Triangle`, `Apu::Noise`) | `apu_test` 1, 2 and 5 test the four main channels' length counters through `$4015` (plan 22, decision 8) | Plan 23 (the rest of both channels) |
| 63 | 2026-11-21 | Reset clears the frame interrupt flag (releasing `FRAME_IRQ`) and writes `$4017`'s last value again; `InterruptLines#reset` also forgets the poll's exceptions | `apu_reset`'s readme, written against the console ("At power and reset, IRQ flag is clear", "last value written to $4017 is written again"); without them an IRQ could follow a reset at once (plan 22 review, decision 4) | — |
| 64 | 2026-11-21 | A DMC fetch halts the CPU through `Cpu#halt(stall_cycles)`, called by the DMC on the cycle it fetches; OAM DMA's stall still comes through `CpuBus#take_stall_cycles` | No query per step for the DMC, and the stall lands when it happens; moving OAM DMA too would reopen plan 22's calibration (plan 23, decision 1). Amends decision 20 | Left by plan 25 (decision 9) |
| 65 | 2026-11-21 | DMC fetches stall 3 cycles for a load (on the `$4015` write) and 4 for a reload | The DMA page's rule at no cost; `apu_test` 7-8 pass (plan 23, decisions 2 and 3; Known gaps: DMC DMA timing) | A later DMA pass |
| 66 | 2026-11-21 | The mixer uses the APU Mixer page's lookup tables (`Apu::Mixer`), `Apu#output` mixing on demand | Two constant reads per sample, within 0.5% of the exact formulas; the per-cycle accumulation belongs to the resampler (plan 23, decisions 5 and 8) | Plan 24 |
| 67 | 2026-11-21 | The frame counter's and the DMC's interrupt flags are one class, `Apu::InterruptFlag(source:)` | Both are set unless inhibited, cleared when inhibited, and drive their own IRQ source; only who clears them on `$4015` differs, which `Apu` decides | — |
| 68 | 2026-11-22 | Audio is mono signed 16-bit PCM at 48 kHz (`Audio::SAMPLE_RATE`), made in the core only when a frontend plays or keeps it | The macOS output device's own rate, so miniaudio does not resample again; without a listener the APU mixes nothing (`@resampler&.add(output)` skips evaluating `output`), as mixing every cycle cost about 9% (plan 24, decisions 1 and 6) | Left by plan 25 (decision 9: the APU and audio are about 14% of a frame) |
| 69 | 2026-11-22 | A box resampler with an exact integer phase, no dynamic rate control | With the audio as the window's master clock there is no drift to correct; band-limited synthesis only if the quality calls for it (plan 24, decision 4) | — |
| 70 | 2026-11-22 | The output filters are a first-order high-pass at 90 Hz and a first-order low-pass at 14 kHz, in the discrete RC form at the output rate | The APU Mixer page's list (no 440 Hz high-pass); the RC form costs one multiply per filter (plan 24, decision 5; Known gaps: low-pass filter near Nyquist) | — |
| 71 | 2026-11-22 | With audio the window is paced by it (`Frontends::AudioPacing`); an underrun is a gap of silence; paused, it queues silence | raylib zero-fills a sub-buffer that runs dry; muting while slow or slowing the pitch would add state for a speed plan 25 is to reach (plan 24, decisions 2 and 7) | When a configuration reaches full speed (the crackle-free check plan 28 could not run) |
| 72 | 2026-11-22 | Flag tests on hot paths are inline, `(value & FLAG) != 0 # glossary: flag-set` (and `flag-clear`); `anybits?`/`allbits?`/`nobits?` stay mandatory off them; `Style/BitwisePredicate` is disabled for the directories of per-dot, per-cycle and per-instruction code (`apu`, `cpu`, `input`, `mappers`, `ppu`), where load-time code (tables, board building) still uses the predicates | Under YJIT and ZJIT `anybits?` is a C call and the operator compiles inline: about 9 ns more per test, and converting every hot-path flag test took a Super Mario Bros. 3 frame from 70.9 to 54.5 ms under YJIT (-23%; plan 25, decision 1, benchmarks.md) | — |
| 73 | 2026-11-22 | The renderer is a per-dot pipeline: it owns the background shift registers (`BackgroundShifters` folded in) and both layers' visibility, composes each pixel itself from the sprite line's entries, asks the priority multiplexer only where both layers are opaque, and the picture reads palette RAM without `PpuBus` | The per-dot chain of objects cost about a third of a Super Mario Bros. 3 frame in calls (vernier); still one `run_dot` per dot, so `@dots` is right at every fetch MMC3's A12 watch reads (plan 25, decision 7) | Ranges of dots and whole tiles since plan 28 (decisions 75 and 76); the composition moved to `PixelComposer` (decision 84) |
| 74 | 2026-11-22 | `Console#run_frame` catches the PPU up to a step's end only from `Ppu#sync_cycle` on: the earlier of its frame timing's next event (VBlank start or end, the next frame) divided by 3 and the board's `earliest_irq_cycle` (MMC3: `cycle + (clocks to the IRQ − 1) × 3`), memoised until a catch-up, register access or reset; `Console#step` still catches up after every step | With a catch-up after every instruction each covered 6-21 dots, too few for ranges to pay; between register accesses the PPU reaches the CPU only through /NMI, the frame's end and the board's IRQ, all predictable with a bound that never comes late, so the output is exact (identical digests). The tracer reads the PPU after each `step` (plan 28, decisions 1-3) | Done for the APU by plan 29 (decision 78) |
| 75 | 2026-11-22 | `Ppu#catch_up` runs ranges within a scanline up to `FrameTiming#last_quiet_dot` (dot 0 on scanlines 241 and 261, the skipped dot on an odd frame's pre-render line with rendering, 340 otherwise) through `Renderer#run_dots`; `Ppu::DotClock`, shared with the renderer, holds the elapsed dots, which the renderer sets before each dot's fetches | The loop lives where the dot count and the frame timing are; a shared clock keeps the board's contract (`Ppu#elapsed_dots` at each fetch) instead of a dot on every PPU bus read (plan 28, decisions 4 and 5) | — |
| 76 | 2026-11-22 | A tile of a visible line whose 8 dots a range covers runs as one unrolled sequence (`RenderSchedule::WHOLE_TILE`), the other dots one at a time | About 15% of a Super Mario Bros. 3 frame under YJIT; the same tile as a `while` loop with the pixel inline and a `case` for the fetches was measured slower than the per-dot path (plan 28, decision 6) | The tile's pixels from a window under fine X since plan 30 (decision 83) |
| 77 | 2026-11-23 | Accuracy shortcuts (a scanline drawn at once regardless of writes in the middle of it, MMC3's IRQ clocked once per line, the sprite 0 hit per line, the audio averaged per sample) enter only as an optional fast mode behind a command-line flag; the exact model stays the default, the one the suite, the test ROMs and the `rake bench:frames` digests run | The study is about the hardware, and the digests are what proves an optimisation changed nothing; a fast mode lets a game be played at full speed without giving that up, at the price of two code paths. The user's choice over never taking a shortcut and over shortcuts by default | When the exact plans 29-31 leave the gap open: each shortcut is proposed with its measured gain and the tests it puts at risk (plan 25, decision 4) |
| 78 | 2026-11-23 | `Console#run_frame` catches the APU up only from `Apu#sync_cycle` on, one past the earlier of the frame counter's next interrupt (or a pending `$4017` write's effect) and the DMC's next fetch, and once more after its loop, to the last step's end; memoised until a catch-up, register write or reset. `Console#step` still catches up after every step | Between register accesses the APU reaches the CPU only through its interrupt flags and the DMC's fetches, both predictable; an event on cycle F happened after the step that crosses F, so F + 1 keeps every IRQ stamp and stall (identical digests). From about 9 900 catch-ups a frame to about 30 (plan 29, decisions 4 and 5) | — |
| 79 | 2026-11-23 | `Apu#catch_up` runs by runs of quiet cycles: each unit tells how far it is quiet (`quiet_cycles`, `quiet_ticks`), a muted channel answering `Apu::NEVER`, and every unit skips the run at once; the cycle with a change runs on its own, and the mix is taken once per run | The mix every cycle was about half of the APU's share, and the mix changes about 250 times a frame. Runs that end at every clock stayed 2-3 cycles long under the noise's fastest period, while the noise was audible on 4% of the cycles; letting muted channels skip clocks makes runs long (plan 29, decisions 1 and 3). About -18% per frame under YJIT | — |
| 80 | 2026-11-23 | A run hands the resampler one level for its cycles (`Resampler#add_run`), which still adds it once per cycle | Adding a level n times and adding n × it differ in the float sum's last bits, and the audio digest would change; an integer accumulator would too, so it belongs to the fast mode (plan 29, decision 2) | — |
| 81 | 2026-11-23 | `Apu::NEVER` is an Integer, 2**60, not `Float::INFINITY` | The runs add and double it on the hot path; an Integer keeps the arithmetic in Fixnums (plan 29, decision 6) | — |
| 82 | 2026-11-23 | A catch-up loop calls a method per step of its loop instead of holding the step's body inline (`Apu#run_cycle`, `#skip`) | Under YJIT a catch-up of thousands of cycles whose `while` held the cycle's body ran about half as fast per cycle as catch-ups of 3 (measured: 4.2 against 2.2 ms per 29 780 cycles without audio); with the body in a method both cost about the same. The interpreter showed no difference (plan 29) | When YJIT changes |
| 83 | 2026-11-23 | A whole tile reads its 8 pixels as a window under fine X of the four 16-bit shift registers, (register × 2^fine X) >> 8, spread one bit per nibble by a load-time table per register into 32 bits, and shifts them by 8 once; the registers stay the only model and the per-dot path is unchanged | Within a whole tile nothing reloads, so the 8 shifts are one; two tiles of 4-bit pixels would be 64 bits, past a Fixnum; a shift by fine X is a method call under YJIT, a multiplication by a power of two is not (plan 30, decisions 2 and 7) | — |
| 84 | 2026-11-23 | `Ppu::PixelComposer` composes the pixels and stores them into the picture's drawn frame through `Picture#colours`; a whole tile is one call drawing 8 pixels unrolled, the background alone when the tile's sprites are hidden, and it takes the frame index computed | Three calls per pixel (`draw`, `shift`, `Picture#draw`) cost more than their arithmetic; a layer shows in a whole tile or in none of it; an index computed inside the unrolled method made it about a third slower under YJIT (plan 30, decisions 1 and 6) | — |
| 85 | 2026-11-23 | `Ppu::Picture` keeps the final pixel of each of the 32 palette entries, rebuilt when palette RAM (which tells its one observer of every write), greyscale or emphasis change | All three are register writes, which catch the PPU up first, so a colour is never stale for a pixel; one table read instead of a palette RAM read, a mask and an OR per pixel (plan 30, decision 4) | — |
| 86 | 2026-11-23 | The board tells its one `PpuBus::Nametables` every mirroring it selects (`nametables=`, `mirroring_changed`), through the base's private `mirroring=` | A board selects a mirroring at power-up or on a register write, which catches the PPU up first, so the nametables are never stale for a fetch; no Hash lookup per nametable access (plan 30, decision 3) | — |
| 87 | 2026-11-23 | The attribute fetch takes its address and the factor that brings its quadrant to bits 7-6 from two load-time tables of 4096 entries indexed by v's low 12 bits | About 14% of a visible line: the address arithmetic and the shift by the quadrant, a method call under YJIT (plan 30, decision 8) | — |
| 88 | 2026-11-23 | `Ppu::SpriteLine` flags each group of 8 columns where an opaque sprite pixel lies (`occupied_tiles`, 32 flags in one array for the life of the line, emptied by `clear`, set by `place`), and a whole tile the flags leave clear composes the background alone | Most tiles hold no sprite pixel; the flags are exact for the whole line, filled on the line before. An array, not an Integer mask: the renderer keeps a reference to it as to the entries, and testing an Integer's bit would be a shift by a varying amount (plan 31, decision 1) | — |
| 89 | 2026-11-23 | A visible line's sprite slot whose 8 dots a range covers runs as one sequence (`RenderSchedule::WHOLE_SLOT`): its first dot's own steps only where it has more than the slot's (257), then `SpriteRenderer#run_slot`, which shares the dot clock, resets OAMADDR once, makes the two fetches on their dots and loads | `SpriteRenderer#run_steps` was about 11% of a frame, called on every dot 257-320 only to reset OAMADDR; nothing within a range changes OAMADDR, so one reset is exact. The pre-render line keeps the per-dot path (plan 31, decisions 2 and 3) | — |
| 90 | 2026-11-23 | The next line's two tiles (dots 321 and 329 of both rendering lines) run as one sequence when a range covers their 8 dots (`RenderSchedule::WHOLE_NEXT_LINE_TILE`): a whole tile without its pixels; lines with no step are still walked dot by dot | Dots 321-340 of a visible line went from about 3.1 to 1.6 µs; skipping the lines with no step measured about 0.3% of a frame, below the noise (plan 31, decision 5) | — |
| 91 | 2026-11-23 | `Ppu::Renderer` is past RuboCop's class length on purpose (`Metrics/ClassLength` disabled on the class) | The background's pixel, its registers and the sequences of 8 dots stay inline in one object, where YJIT calls them through self (plan 25); the user chose this over extracting the shift registers (plan 31) | — |
| 92 | 2026-11-23 | The window looks each pixel's colour up on the GPU: `Frontends::RaylibPicture` uploads the frame buffer's values (`FFI::Pointer#put_array_of_uint16`, no allocation) into a grey-and-alpha texture and a fragment shader reads the colour from a 512×1 palette texture; no CPU path is kept | `Frontends::Palette.rgb` took about 2.9 ms a frame and allocated a frame's worth of strings (31 GC runs per 1200 frames); `present` went from about 3.2 to 0.8 ms and the GC runs to 2. `pack('S<*')` costs as much as the lookup, and the best CPU lookup would leave about 1.8 ms (plan 32, decision 1) | — |
| 93 | 2026-11-23 | A palette shader that does not compile or link raises `Frontends::RaylibPicture::ShaderError` when the window opens, with raylib's log saying why, and `ruby-nes` reports it as an error, not a backtrace (`CommandLine::RaylibWindow`) | raylib-bindings ships OpenGL 3.3 builds; a fallback to the RGB path would keep two paths and two specs. raylib replaces a shader that compiles but does not link with its default one, which `IsShaderValid` accepts, so the picture also checks the id against the default shader's (plan 32, decision 2 and review) | — |
| 94 | 2026-11-23 | Only the slow units bound `Apu#catch_up`'s runs (the frame counter, the pulses, the DMC); the triangle and the noise go through each run clock by clock in `Apu::FastChannels`, handed the slow channels' outputs once per run, and hand the resampler the run in parts | Super Pitfall's sound effects play the triangle at period 0 and the noise at 4 cycles, which cut runs to every cycle: those frames took 25-37 ms against about 15. In play the mean fell from 16.7 to 14.4 ms and the worst frame from 28-30 to 18, digests unchanged (plan 33, decision 1) | — |
| 95 | 2026-11-23 | `Apu::FastChannels` is a collaborator, not private methods of `Apu` | With the run inside, `#catch_up`'s spec tree came to 27 leaves, 6 levels deep, for three jobs; keeping one unit is worth it only for performance, and the split costs one call per run, not per clock (plan 33, decision 1) | — |
| 96 | 2026-11-23 | `Audio::Resampler#add_run` takes parts of any length: 0 cycles add nothing, 1 goes straight to `#add` | The fast channels hand thousands of one-cycle parts a frame; the length is decided in one place, and `#add` makes the same float additions (plan 33, decision 2) | — |
| 97 | 2026-11-25 | Battery saves live in the user's data directory, `$XDG_DATA_HOME/ruby-nes/saves/` (else `~/.local/share/ruby-nes/saves/`), each the raw 8 KiB of PRG RAM named after the ROM's file name with `.sav` | Works whatever folder the ROMs are in, beside `~/.config/ruby-nes/`; plans 35 and 37 keep their files there. The raw format and the name are other emulators', so a save moves between them (plan 34, decisions 1 and 2) | — |
| 98 | 2026-11-25 | The window writes the running game's save every 300 emulated frames (about 5 s) when the RAM changed since the last write, and when the run ends; no file until the RAM changes | Comparing 8 KiB every few seconds keeps the bus's hot path untouched, where a dirty flag would add work to every write to `$6000-$7FFF`; a killed process loses at most one interval (plan 34, decisions 4 and 6) | — |
| 99 | 2026-11-25 | Headless runs never read or write saves, with no option to | Their digests stay reproducible; the window's specs exercise the keeper with a stand-in frontend (plan 34, decision 3) | When a tool-assisted run needs a save |
| 100 | 2026-11-25 | A save of the wrong size stops the run before the window opens; writes are atomic (a temporary file of its own, created exclusively, `fsync`, rename) | A save is never overwritten by mistake, a crash mid-write leaves the old save or the new one, and two windows of the same game never write into each other's temporary file (plan 34, decisions 5 and 7) | — |
| 101 | 2026-11-25 | A periodic battery save write that fails is a warning and the game goes on; the write at the end raises | The RAM in memory is intact, so stopping the game would lose more than it saves; the next interval tries again (plan 34, review) | — |
| 102 | 2026-11-25 | Port 1 is the keyboard and the first gamepad combined, port 2 the second gamepad, with no config; a gamepad is read only while raylib says it is available, asked every frame; ports follow raylib's pad numbers, so with two pads in, pulling out the first leaves the second on port 2 | One person with one pad plays as player 1 with the keyboard at hand, and raylib follows plugging in and out itself; renumbering pads on the fly would hand player 1's controller to player 2 mid-game (plan 36, decisions 2 and 6; review) | When someone needs to assign pads to ports, or a device raylib does not map takes gamepad 0 |
| 103 | 2026-11-25 | `gamepad:` binds controller buttons to raylib's gamepad button names, by letter on a SNES pad (A right and X top are A, B bottom and Y left are B); hotkeys stay on the keyboard; `Frontends::Keyboard` became `Frontends::Controls`, serving keys and buttons | The letters match what a person reaches for; the pad combination for a menu is plan 38's; the binding logic had nothing of a keyboard (plan 36, decisions 1 and 3) | Plan 38 (hotkeys on the pad) |
| 104 | 2026-11-25 | The left stick drives the directions past a dead zone of 0.5 | Pads with analog sticks play too; resting a little off centre holds nothing (plan 36, decision 5) | — |
| 105 | 2026-11-25 | `gamepad_mappings:` is handed to raylib's `SetGamepadMappings` unchecked | raylib (GLFW) returns success for any text, skipping lines it cannot read silently, so there is no refusal to report; the README says to test the pad (plan 36, decision 4) | — |
| 106 | 2026-11-25 | On Linux, before raylib opens the audio device, `PULSE_LATENCY_MSEC` is set to 15 unless the environment has it (`Frontends::AudioDeviceLatency`) | raylib's stream is two sub-buffers of 800 samples, and a device request that does not fit beside one is padded with silence: through the Pulse client (about 1024 samples a request) the window ran at 53.4 fps; 5-20 ms measured at 60, 25 at 53.5. A user's value is kept; sub-buffers of two frames would release frames in pairs and double the audio's delay (plan 39) | When a backend other than the Pulse client (ALSA directly, JACK) asks for more than 800 samples at a time, or when `Frontends::Raylib::SAMPLES_PER_FRAME` or the sample rate changes |
| 107 | 2026-11-25 | A save state is Marshal of the console's components, the board leaving its ROM out (nil in its place, so a restored board keeps a new one's shape) and taking it back from the cartridge; `Console#restore` swaps the components in, keeping the console | The emulator's state is plain Ruby objects, so Marshal writes it whole and exact (a restored console runs to the same frames and audio, spec); without the ROM a state is 9-18 KB compressed; holders of the console (the driver, the battery keeper) need no telling. A hand-written `state`/`restore` per component would have to follow every later change (plan 35, decision 1) | When a component holds something Marshal cannot write (a Proc, an IO) |
| 108 | 2026-11-25 | A state is restored only when its header's ROM digest (SHA-256 of PRG and CHR), sample rate (0 without sound) and code fingerprint match the console's, checked before `Marshal.load`. The fingerprint is the console's shape (`Saves::Shape`: every reachable object's class and instance variable names) with the core's constants (`Saves::ConstantsDigest`). A snapshot Marshal cannot load is refused too. States are read only from the emulator's own directory, and the README warns against others' | Marshal can build any object, so the check runs first and the file must be ours. The console's shape does not change as it runs (measured on six games), so a different shape means code that would find a variable nil. A state carries the constant tables it points at (waveforms, a frame counter's steps) by value, so a changed table must refuse it too. A console with sound holds more objects than one without, so the refusal names `--no-audio`. The gem's version never changes while the code does, and a digest of the sources would refuse states after any comment (plan 35, decision 2; review) | When a change keeps the shape and the constants but changes what a variable means: bump `Saves::ConsoleState::FORMAT_VERSION` |
| 109 | 2026-11-25 | Ten state slots per game, `states/<ROM file name>/<slot>.state` and `.png` under the data directory; F5 saves over the current slot at once, F7 loads, F6/F8 pick the slot, wrapping; a game starts on its latest slot; the battery RAM follows a loaded state; the frontend drops its queued audio after a load and shows a message for 120 frames | Several emulators' layout; F7 after opening resumes where the player left off; leaving the battery RAM out would not return the game to the moment (plan 35, decisions 3-9) | Plan 38 (a pause menu listing the slots) |
| 110 | 2026-11-25 | The ROM browser's menu is an NES frame, 256 × 240 palette indices composed in Ruby (`Frontends::Browser::Screen`) and drawn by `Frontends::RaylibPicture` like a game; its text sits on the 8 × 8 grid, in an 8 × 8 upper case font of our own (`Frontends::Browser::PixelFont`), within lines 8-231 | Colours of the NES palette by construction and no new drawing code in the window; specs read the screen back as text; composing a frame takes about 0.6 ms under YJIT; raygui's widgets have a tool's look (plan 37, decisions 3 and 4) | Plan 38 (its screens) |
| 111 | 2026-11-25 | The preview of the game in focus is its own silent console: a cached save state (`previews/<ROM SHA-256>.state`) restored at once as the still picture, then run live after 30 frames of rest; with none, it runs from power-up and the state is cached at the end of the first second showing 30 different pictures (`Frontends::Browser::MotionWatch`), or after a minute | Deterministic emulation makes the ROM its own video; the six local games move after 2-22 s; counting frames that differ from the one before found Super Pitfall's blinking title moving 20 s before its demo; a background scan of every ROM was declined as more code and a busy CPU (plan 37, decision 2) | When a game is found whose picture moves before its demo, or a list too long to wait for |
| 112 | 2026-11-25 | One window and one audio stream for a browser session, a console per game; Escape goes up a level (a game started from the list returns to it, the list quits) and the close button ends the session (`Frontends::Base#closed?`, `#next_screen`); the menu is navigated with controller 1's buttons | The window outlives a game; the menu queues silence so the audio keeps pacing it; Escape quitting a game outright would lose the list; NES menus read the controller (plan 37, decisions 5-7) | Plan 38 (Escape in a game opens its pause menu; the pad returns to the list) |
