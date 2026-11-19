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
|   Cpu#step -> cycles;  Ppu advances cycles * 3 dots;  Apu advances cycles  |
+----------------------------------------------------------------------------+

  +-----+   CPU bus ($0000-$FFFF)
  | Cpu |----+-------------+---------------+------------------+-----------------+
  +-----+    |             |               |                  |                 |
         internal RAM   PPU registers   APU and I/O         test mode       Cartridge
         2 KiB          $2000-$3FFF     registers           (disabled)      $4020-$FFFF
         $0000-$1FFF       |            $4000-$4017         $4018-$401F     (mapper)
                           |            (APU, controllers,                      |
                           v             OAM DMA)                               |
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
  1. **Interrupt lines** — NMI from the PPU, IRQ from the APU and mappers — set as levels with `Cpu#nmi_line=` and
     `Cpu#irq_line=`, and read by the CPU between instructions (plan 07).
  2. **CPU stall cycles** — OAM DMA (a write to `$4014`, plan 11) and DMC sample fetches (plan 23) halt the CPU for a
     number of cycles. The bus reports the stall and `Cpu#step` adds it to the cycles it returns: after each step,
     `@cycles += bus.take_stall_cycles(@cycles)`, the argument being the CPU cycle the halt falls on.

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

`CpuBus` has three slots, given as keywords to `CpuBus.new` and each defaulting to `CpuBus::Disconnected`:
`ppu_registers:` (`$2000-$3FFF`, handed the address already mirrored down to `$2000-$2007`), `io_registers:`
(`$4000-$4017`) and `mapper:` (`$4020-$FFFF`). `$4018-$401F` reach no device. A device answers:

- `cpu_read(address, data_bus)` → the byte left on the data bus after the read. A device that does not drive the bus
  at that address returns `data_bus` untouched (open bus); a register that drives only some bits keeps the others
  from `data_bus`. The bus stores every result as the next `data_bus`; writes do not change it (plan 04, decision 1).
- `cpu_write(address, value)`.

`CpuBus` also owns the **OAM DMA unit**, `CpuBus::OamDma` (plan 11, decision 2): a write to `$4014` starts it instead
of reaching the `io_registers:` slot (reads of `$4014` still go to the slot). Its collaborators are the bus's own: it
reads the page through `CpuBus#read` and writes each byte to `ppu_registers.cpu_write($2004, byte)`, so the bytes land
in OAM from OAMADDR on. The copy happens at once; the 513 or 514 cycles it costs come back through
`CpuBus#take_stall_cycles(halt_cycle)`. Get cycles are the even CPU cycles by convention (see Known gaps).

### Mapper interface

Every board in `Ruby::Nes::Mappers` (built by `Mappers.build(cartridge)` from the iNES mapper number) answers the CPU
device interface above plus:

| Method | Returns |
|---|---|
| `ppu_read(address)` | the pattern table byte, for `$0000-$1FFF` (the PPU bus never hands anything else) |
| `ppu_write(address, value)` | kept by CHR RAM, ignored by CHR ROM |
| `mirroring` | the nametable arrangement the board selects: `:horizontal`, `:vertical`, `:single_screen_lower`, `:single_screen_upper` or `:four_screen` (asked on every nametable access, so a board may change it at any time) |
| `irq?` | whether the board holds the CPU's IRQ line low |

No base class yet (plan 19 extracts one); a scanline/A12 hook for MMC3 is shaped by plan 21.

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
  brings (pages 2 and 3). Address bits 10-11 pick the logical nametable; the mapper's `mirroring` picks its physical
  page ([Mirroring](https://www.nesdev.org/wiki/Mirroring), whose names the iNES header follows; the PPU nametables page
  names the arrangements the other way round):

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

**Instruction-level catch-up** (decision 1):

1. `Cpu#step` executes one whole instruction (plus any stall cycles) and returns the CPU cycles it took.
2. `Console` advances the PPU `cycles * 3` dots and the APU `cycles` ticks.
3. Interrupt lines raised during that catch-up are seen by the CPU before its next instruction.
4. A frame ends when the PPU signals it; the frontend then takes the frame buffer (and, later, the audio samples).

**Relation to the [Catch-up](https://www.nesdev.org/wiki/Catch-up) page.** The page's recipe is to find the next
time one component could affect another (for example the CPU writing to a PPU register), run the least predictable
component (the CPU) up to that time, then run the others up to it. Synchronising after *every* instruction is the
crudest form of that recipe: the sync points do not depend on what the instruction touched, and an access in the
middle of an instruction is not synchronised at all.

**Direction of the error.** While an instruction runs, the PPU, APU and mapper are still at the time the instruction
*started*; they lag the CPU by up to the instruction's length. So:

- a CPU **write** reaches them *early*: they apply it before running the dots or ticks that, on real hardware, happen
  before the write;
- a CPU **read** sees *stale* state: a flag that the hardware would have set during the instruction (the VBlank flag
  read through `$2002`, for example) is not set yet.

The page lists the cases where this matters: PPU register writes (especially `$2004`) around sprite 0 hit, mapper or
PPU register writes around the mapper IRQ, and APU register writes around the frame IRQ and length counters.

**Upgrade path**, from cheaper to more exact:

1. **Catch up on register access.** Before the CPU bus services an access to `$2000-$3FFF`, `$4000-$4017` or a mapper
   register, advance the PPU and APU to the CPU's current cycle inside the instruction. This needs each bus access to
   know its cycle offset within the instruction, and removes the error for every case above.
2. **Tick on every bus access.** Advance the PPU and APU on every CPU read and write. Exact, with the most calls.

Plan 12 chooses (with the `ppu_vbl_nmi` test results, before rendering is built on top); plan 21 may need it for the
MMC3 scanline IRQ. The `Cpu#step` interface stays in every option; only where the PPU and APU are advanced changes.

## Layout and loading

| Path | Constant | Contents |
|---|---|---|
| `lib/ruby/nes.rb` | `Ruby::Nes` | entry point: `require_relative` of every component, in dependency order |
| `lib/ruby/nes/console.rb` | `Ruby::Nes::Console` | wires components, runs the clock |
| `lib/ruby/nes/cartridge.rb` | `Ruby::Nes::Cartridge` | the loaded cartridge (header, PRG, CHR) |
| `lib/ruby/nes/cartridge/` | `Ruby::Nes::Cartridge::Header`, `::Loader`, errors | iNES parsing |
| `lib/ruby/nes/mappers.rb` | `Ruby::Nes::Mappers` | `Mappers.build` factory |
| `lib/ruby/nes/mappers/` | `Ruby::Nes::Mappers::Nrom`, `::Mmc3`… | one file per mapper (a shared base is extracted in plan 19) |
| `lib/ruby/nes/cpu_bus.rb` | `Ruby::Nes::CpuBus` | CPU address decoding, RAM, open bus |
| `lib/ruby/nes/cpu_bus/` | `Ruby::Nes::CpuBus::Disconnected`, `::OamDma` | the device in an empty slot; the OAM DMA unit the bus owns |
| `lib/ruby/nes/cpu.rb` | `Ruby::Nes::Cpu` | registers, operand fetch, `step`, interrupts |
| `lib/ruby/nes/cpu/` | `Ruby::Nes::Cpu::Status`, `::Stack`, `::Shifter`, `::AddressingModes`, `::Dispatch`, `::Opcodes`, `::Interrupts`, `::InterruptLines` | status flags, stack, the shift/rotate unit, addressing modes, the opcode dispatch and reset/NMI/IRQ (mixins of `Cpu`), the opcode table of all 256 opcodes (mnemonic, mode, base cycles, official or not), the NMI edge detector and IRQ level |
| `lib/ruby/nes/cpu/instructions/` | `Ruby::Nes::Cpu::Instructions::LoadStore`, `::Arithmetic`, `::Branches`…, `::ReadModifyWriteCombos`, `::ImmediateCombos`, `::Unstable` | one mixin of `Cpu` per instruction group, each instruction a method taking the resolved effective address; the last three hold unofficial opcodes only (plan 09) |
| `lib/ruby/nes/ppu_bus.rb` | `Ruby::Nes::PpuBus` | PPU address decoding |
| `lib/ruby/nes/ppu_bus/` | `Ruby::Nes::PpuBus::Nametables`, `::PaletteRam` | VRAM through the mirroring, palette RAM |
| `lib/ruby/nes/ppu.rb` | `Ruby::Nes::Ppu` | the register decoder and the PPU's I/O latch; timing and rendering later |
| `lib/ruby/nes/ppu/` | `Ruby::Nes::Ppu::ScrollRegisters`, `::Oam`, `::DataPort`… | v/t/x/w, OAM and OAMADDR, PPUDATA; renderer pieces later |
| `lib/ruby/nes/apu.rb`, `apu/` | `Ruby::Nes::Apu`, `Ruby::Nes::Apu::…` | channels, frame counter, mixer |
| `lib/ruby/nes/input/` | `Ruby::Nes::Input::Controller` | controllers |
| `lib/ruby/nes/frontends/` | `Ruby::Nes::Frontends::Base`, `::Headless`… | headless, raylib/sdl2 (later) |
| `lib/ruby/nes/debug/` | `Ruby::Nes::Debug::Tracer`, `::FrameDump`… | tooling off the hot path |
| `lib/ruby/nes/bits.rb` | `Ruby::Nes::Bits` | the bit constants hot paths use inline (`BYTE_MASK`, `PAGE_MASK`…) and readable bit helpers for code off the hot path |
| `lib/ruby/nes/cli.rb` | — | command line (plan 18) |
| `spec/support/test_roms.rb`, `spec/support/test_roms/` | `TestRoms`, `TestRoms::Manifest`, `::Fetcher`… | test ROM harness (plan 02): test tooling, not shipped in the gem |
| `spec/support/nestest.rb`, `spec/support/nestest/` | `Nestest`, `Nestest::Log`, `::Runner`, `::Divergence` | nestest in automation mode compared with its reference trace (plan 08): test tooling, also used by `rake nestest:diff` |
| `bench/cpu.rb`, `bench/cpu_benchmark.rb`, `bench/cpu_benchmark/` | `CpuBenchmark`, `CpuBenchmark::Workload`, `::Session`, `::Report`… | the CPU benchmark (plan 10): nestest looped under no JIT, YJIT or ZJIT, run by `rake bench:cpu` and `rake bench:variants`; specs in `spec/cpu_benchmark/` |
| `bench/cpu_benchmark/variants/` | — | hot-path experiments that reopen core classes, each loaded only inside a benchmark process of its own (plan 10, decision 3) |

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
`cpu_read`/`cpu_write`/`ppu_read`/`ppu_write`, the PPU dot and the APU tick, and the `Console` loop around them.
Loading a ROM, the CLI, frontends (outside the per-frame copy), debug tooling and specs are not hot paths.

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

## Readability

The code mirrors hardware but must read like prose to someone who does not know the NES by heart. The rules apply to
production code and specs alike.

- No single-letter or meaningless names (`a`, `x`, `tmp`, `val`), block parameters and loop indices included
  (`accumulator`, `index_x`, not `a`, `x`).
- No abbreviations or acronyms in names — with **exception 1** below.
- Prefer named methods to operator-like ones when Ruby offers them: `first.intersection(second)` over
  `first & second`; `union`, `difference`.
- **Flag tests always use `anybits?`, `allbits?` or `nobits?`** (`status.anybits?(CARRY_FLAG)`,
  `value.anybits?(SIGN_BIT)`), on hot paths too: they are C methods, and RuboCop's `Style/BitwisePredicate` rejects
  the `& FLAG != 0` form.
- Masks, flags, addresses and other magic numbers are named constants, citing the NESdev page they come from.
- Off hot paths, other bit arithmetic goes through the intention-revealing helpers of `Ruby::Nes::Bits`
  (`Bits.wrap_to_byte(value)`, `Bits.high_byte(address)`) — with **exception 2** below for hot paths.
- Small methods with intention-revealing names over comments that explain what a block does.

**Exception 1 — hardware acronyms** (decision 4). Documented hardware names are kept in class and constant names
(`Cpu`, `Ppu`, `Apu`, `Oam`, `Dmc`, `PPUCTRL`) because they are what the reference documentation uses and what a reader
searches for. Each is expanded in [`GLOSSARY.md`](GLOSSARY.md#hardware-terms), and the class or constant comment
expands its own. Standard computing acronyms used by the tooling (URL, HTTP, YAML, SHA-256, SSL, JSON, and the JIT
names JIT, YJIT, ZJIT) are allowed on the same terms (decision 5): each is expanded in
[`GLOSSARY.md`](GLOSSARY.md#computing-terms). Anything else is spelled out.

**Exception 2 — inline bit operations on hot paths** (decision 3). On hot paths the operators `&`, `|`, `^`, `~`,
`<<`, `>>` and the signed-byte idiom are written inline, so no method call is paid per cycle, provided that

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

## Known gaps

Hardware behaviour deliberately not modelled yet, each with the plan that revisits it.

| Gap | Hardware | Revisit in |
|---|---|---|
| Dummy reads | On a page cross an indexed read "reads an incorrect location first, a location that is smaller by one page", and indexed writes always read before writing ([6502_cpu.txt](https://www.nesdev.org/6502_cpu.txt)). The emulator reads only the effective address, so a dummy read of a register with read side effects (`$2002`, `$2007`) or its effect on open bus is missing. | Plan 12, with the `cpu_dummy_reads` test ROM |
| Read-modify-write double write | `ASL`, `LSR`, `ROL`, `ROR`, `INC` and `DEC` on memory "first [write] the original value back to memory" before the modified one ([Instruction reference](https://www.nesdev.org/wiki/Instruction_reference)); so do the unofficial combos (`SLO`, `RLA`, `SRE`, `RRA`, `DCP`, `ISB`): "Read-Modify-Write instructions write unmodified data, then modified" ([6502_cpu.txt](https://www.nesdev.org/6502_cpu.txt)). The emulator writes only the result, so a device that reacts to every write misses the first one: the MMC1 serial port "ignores every write after the first" on consecutive cycles, which "only happens when the CPU executes read-modify-write instructions" ([MMC1](https://www.nesdev.org/wiki/MMC1)). | Plan 20 (MMC1) |
| Interrupt polling point | Interrupts are polled "during the final cycle of the instruction", and what matters is the line status "at the end of the second-to-last cycle"; branches poll before their operand fetch and "not before the third CPU cycle on a taken branch" ([CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts#Branch_instructions_and_interrupts)). The emulator polls before each instruction, after the console caught up, so a line raised during an instruction's last cycle is taken one instruction early, and taken branches get no special case. | Plan 12 (clock model), with the `cpu_interrupts_v2` test ROM |
| IRQ delay after `CLI`, `SEI`, `PLP` | These "change the I flag after polling for interrupts", so "executing CLI will execute the next instruction before the CPU invokes the IRQ handler", and an IRQ pending when `SEI` runs is still taken once ([CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts#Delayed_IRQ_response_after_CLI,_SEI,_and_PLP)). The emulator polls with the new I, so the IRQ comes one instruction early after `CLI`/`PLP` and is lost after `SEI`. `RTI` acts immediately, as modelled. | Plan 12, with `cpu_interrupts_v2` |
| Interrupt hijacking | An NMI asserted during the first four ticks of `BRK` sends it through the NMI vector (with B still set in the pushed flags), and "an NMI can hijack an IRQ" ([CPU interrupts](https://www.nesdev.org/wiki/CPU_interrupts#Interrupt_hijacking)). The emulator finishes `BRK` or the IRQ through `$FFFE` and takes the NMI on the next step. | Plan 12, with `cpu_interrupts_v2` |
| Jammed CPU | The `JAM` opcodes "halt the CPU until reset" ([CPU unofficial opcodes](https://www.nesdev.org/wiki/CPU_unofficial_opcodes)); no reference found says what the bus does meanwhile, how the cycles count, or whether NMI and IRQ act on a jammed CPU. The emulator's choice is a convention: each `Cpu#step` touches no bus, takes no interrupt and returns 2 cycles (`Cpu::JAMMED_STEP_CYCLES`), and the `JAM` opcode itself costs 2. **Technical debt:** search deeper (Visual6502 simulations, "No More Secrets") and replace the convention with a sourced behaviour. | A later CPU pass (no plan yet) |
| Unstable unofficial opcodes | `ANE` (`XAA`), `LAX #imm`, `SHA` (`AHX`), `SHX`, `SHY`, `TAS` and `LAS` depend on the chip, the temperature and the RDY line ("No More Secrets", [csdb.dk/release/?id=198357](https://csdb.dk/release/?id=198357)). The emulator uses the documented formulas without DMA, the magic constants the document advises for emulators ($EF for `ANE`, $EE for `LAX #imm`), and Z and N from the result ([Visual6502 wiki](https://www.nesdev.org/wiki/Visual6502wiki/6502_Opcode_8B_(XAA,_ANE)) for `ANE`, inferred for `LAX #imm`; "No More Secrets" says both follow A before the instruction). `LAX #imm`'s $EE comes from a C64 source; NES emulators are said to use $FF. | Plan 12, with `instr_test-v5` (it tests `LAX #imm`, `SHX` and `SHY`) |
| PPU I/O latch decay | "At least one bit in this value decays after 3ms to 30ms" ([PPU registers](https://www.nesdev.org/wiki/PPU_registers)). The latch keeps its value forever. | Plan 12 (time exists), with `ppu_open_bus` |
| OAM DMA alignment | Get and put cycles "are aligned to the first and second halves of the APU clock", and "At power-on, whether the first CPU cycle is get or put is random" ([DMA](https://www.nesdev.org/wiki/DMA)). The emulator takes even CPU cycles, counted from `Cpu.new`, as get cycles (a convention; plan 11, decision 3 compares it with Mesen2, which reaches the same alignment counting 8 reset cycles and odd get cycles), so a `$4014` write on an even cycle stalls 513 cycles and on an odd one 514. The copy also happens at once, before the stall, so the PPU sees OAM complete one instruction early. | Plan 23 (DMC DMA shares the get/put rule) |
| PPU register writes after reset | `$2000`, `$2001`, `$2005` and `$2006` ignore writes "until reaching the pre-render scanline" after power and reset ([PPU power up state](https://www.nesdev.org/wiki/PPU_power_up_state)). They are always accepted. | Plan 12 |
| OAMDATA and PPUDATA during rendering | OAMDATA writes during rendering "do perform a glitchy increment of OAMADDR", its reads "expose internal OAM accesses"; PPUDATA "will update v in an odd way" ([PPU registers](https://www.nesdev.org/wiki/PPU_registers), [PPU scrolling](https://www.nesdev.org/wiki/PPU_scrolling)). Both behave as outside rendering. | Plans 13, 14 |
| Byte under a palette read | A PPUDATA read of the palette fills the buffer from "a normal read from PPU memory at the specified address, "underneath" the palette data" ("usually mirrored nametables"). The emulator reads the nametable byte `$1000` below (the `$2F00-$2FFF` mirror), an inference from "$3000-3EFF is usually a mirror of" `$2000-$2EFF`. | When a board maps `$3000-$3FFF` differently |

## Frame buffer contract

- The PPU writes **palette indices** (0–63; a 6-bit value selects one of the 64 colours, see
  [PPU palettes](https://www.nesdev.org/wiki/PPU_palettes)) into a preallocated buffer of 256 × 240 entries, row by
  row. Colour emphasis bits are added on top when the PPU plans get there.
- Converting indices to RGB, scaling and presenting are the **frontend's** job. The core never depends on a graphics
  library.

## Concurrency

No threads and no Ractors in the core. CPU, PPU and APU are coupled at cycle granularity, so passing messages between
them would cost more than it saves. Revisit only if profiling finds a separable stage (for example audio
presentation, in a frontend).

## Decisions log

| # | Date | Decision | Reason | Revisit in |
|---|---|---|---|---|
| 1 | 2026-11-17 | Clock model: instruction-level catch-up | Simpler, fewer calls per instruction in Ruby | Plan 12 (VBlank/NMI tests), plan 21 (MMC3 IRQ) |
| 2 | 2026-11-17 | Memory container: `Array` of Integer | Most readable; plan 10 measured a binary `String` −4% and `IO::Buffer` −24% under YJIT, both slower without a JIT ([benchmarks](benchmarks.md#findings)) | — |
| 3 | 2026-11-17 | Hot paths write bit operations inline with named constants and `# glossary:` tags; flag tests always use `anybits?`/`nobits?` | No method call per cycle, meaning still one lookup away; RuboCop enforces the predicates. Plan 10: `Bits` helpers on the per-instruction path cost nothing measurable under YJIT and ZJIT but 14% without a JIT, and that path is only a lower bound of a full conversion | Plan 25 (measure the whole hot path converted before narrowing the exception) |
| 4 | 2026-11-17 | Hardware acronyms kept in names, expanded in the glossary | They match the reference documentation readers search | — |
| 5 | 2026-11-17 | Standard computing acronyms (URL, HTTP, YAML, SHA-256, SSL; JSON, JIT, YJIT, ZJIT since plan 10) allowed in tooling names, expanded in the glossary | They are what the libraries and protocols call them; spelling them out (`address` for URL) would clash with emulator terms | — |
| 6 | 2026-11-18 | The status register is a `Cpu::Status` object holding one boolean ivar per flag; the byte is composed for pushes and the trace, split by pulls | The object hides the representation, so plan 10 could swap it alone: one ivar per flag measured +5% under YJIT, +7% without a JIT and +5% under ZJIT against one Integer with bit masks (the first representation, 2026-11-18) | Plan 25 |
| 7 | 2026-11-18 | The page-cross cycle of indexed reads is charged by `_for_read` resolvers; write and read-modify-write instructions use the plain ones | Tell, don't ask: no flag to query, no second return value | — |
| 8 | 2026-11-18 | Dummy reads are not modelled (see Known gaps) | They matter only for registers with read side effects and open bus, which need the PPU | Plan 12 |
| 9 | 2026-11-18 | Opcode dispatch is a `case` on the opcode's high nibble whose `when`s each hold a `case opcode` of that row, with an integer literal per `when` (`Cpu::Dispatch#execute`), laid out as the opcode matrix; the only method exempt from the size and complexity Metrics cops | `opt_case_dispatch` with no `Proc#call` or `send` per instruction, a shape Spinel can type, the whole opcode map in one place. Two levels since plan 10: one `case` of 256 `when`s is a linear chain of `Integer#===` under ZJIT; the two-level `case` measured +21% under YJIT and +261% under ZJIT (−6% without a JIT), ahead of a table of lambdas under YJIT | Plan 25 |
| 10 | 2026-11-18 | Instructions are spelled-out methods (`load_accumulator`) in one `Cpu` mixin per group; mnemonics are data in `Cpu::Opcodes` | The readability rule against abbreviations; the tracer still finds the mnemonic | — |
| 11 | 2026-11-18 | The read-modify-write double write is not modelled (see Known gaps) | Only devices that react to every write notice it; none exists before MMC1 | Plan 20 |
| 12 | 2026-11-18 | `Cpu.new` takes one optional keyword per register, `stack_pointer:` included; `Metrics/ParameterLists` is disabled on that method alone | The list is as long as the register file; specs declare the state instead of mutating it. The all-zero defaults are the state before the power-up reset sequence: power-up is `Cpu.new` + `Cpu#reset` (plan 07) | — |
| 13 | 2026-11-18 | Interrupt lines are levels set with `Cpu#nmi_line=` and `Cpu#irq_line=`; `Cpu::InterruptLines` detects the NMI's rising edge, keeps it pending until taken, and names the vector to take (NMI first, then IRQ unless the status's I is set); reset discards a pending NMI; the console combines the IRQ sources and sets the line after each catch-up (plan 12 decides) | On hardware the edge detector is in the CPU, so enabling NMI in PPUCTRL during VBlank needs no special case and several IRQ sources combine with `\|\|`; one object keeps edge, level, masking and priority out of `Cpu#step`. Plan 10: inlining the poll in `Cpu#step` measured 0% to +6% under YJIT across runs, no clear winner | — |
| 14 | 2026-11-18 | An interrupt is a `Cpu#step` of its own: before the opcode fetch, `step` takes the interrupt and returns 7 cycles; reset also costs 7 cycles | Lines raised while the console catches up after an instruction are seen before the next one; the tracer sees an interrupt as one step; reset "goes through the same sequence" | Plan 12 (clock model) |
| 15 | 2026-11-18 | The interrupt polling point, the `CLI`/`SEI`/`PLP` delay and interrupt hijacking are not modelled (see Known gaps) | They depend on timing inside an instruction, which instruction-level catch-up does not have | Plan 12, with `cpu_interrupts_v2` |
| 16 | 2026-11-18 | All 256 opcodes have a `Cpu::Opcodes` entry and a dispatch `when`; unofficial entries are marked (`Opcode#official?`) and traced with `*`, as nestest.log marks them; the seven unstable ones follow "No More Secrets" (see Known gaps) | No opcode raises: nestest's full log, `instr_test-v5` and any game that hits an unofficial opcode run on | Plan 12 (`instr_test-v5`) |
| 17 | 2026-11-18 | A `JAM` opcode puts the CPU in a jammed state (`Cpu#jammed?`) that only `Cpu#reset` clears; a jammed step costs 2 cycles and touches nothing (see Known gaps) | The frontend can show the halt, and the console keeps its clock running as the hardware does | When a source for the jammed behaviour is found |
| 18 | 2026-11-18 | Each row's column 2 is its `case`'s `else` (the `JAM` in 12 rows, the opcode `$x2` in rows 8, A, C and E) and row F is the outer `else`; repeated bodies keep one `when` per opcode (`Lint/DuplicateBranch` disabled on the two rows that need it) | A `when` for every value leaves the implicit `else` unreachable, and Ruby's branch coverage counts it; the map stays readable byte by byte | — |
| 19 | 2026-11-18 | YJIT is the project's default JIT | Plan 10: fastest with every variant measured, 16.4 emulated MHz (915% of real time) on nestest against 9.0 for ZJIT and 3.7 without a JIT ([benchmarks](benchmarks.md#findings)) | Plan 25 (whole frames) |
| 20 | 2026-11-18 | OAM DMA is `CpuBus::OamDma`, owned by `CpuBus`, which routes `$4014` writes to it; the stall comes back through `CpuBus#take_stall_cycles(halt_cycle)`, added by `Cpu#step` after every step; even CPU cycles are get cycles | The DMA's collaborators are the bus's own (CPU reads, `$2004` writes), so no circular wiring, and the `io_registers:` slot stays for the APU and controllers; DMC DMA (plan 23) reports through the same channel. The query per step measured about −8% under YJIT on nestest | Plan 23; plan 25 (a push model) |
| 21 | 2026-11-18 | The PPU's I/O latch is modelled without decay; `Ppu#cpu_read` ignores the CPU data bus | Write-only registers and PPUSTATUS's bits 4-0 answer it; decay needs time (Known gaps) | Plan 12 |
| 22 | 2026-11-18 | `PpuBus::Nametables` asks the mapper's `mirroring` on every access and maps it through a constant table; 4 KiB of VRAM support four-screen | MMC1, MMC3 and AxROM change the mirroring at runtime; four-screen costs one table row | Plan 25 (measure the lookup) |
