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
  1. **Interrupt lines** — NMI from the PPU, IRQ from the APU and mappers — read by the CPU between instructions.
  2. **CPU stall cycles** — OAM DMA (a write to `$4014`, plan 11) and DMC sample fetches (plan 23) halt the CPU for a
     number of cycles. The bus reports the stall and `Cpu#step` adds it to the cycles it returns.

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
| `lib/ruby/nes/mappers/` | `Ruby::Nes::Mappers::Base`, `::Nrom`, `::Mmc3`… | one file per mapper |
| `lib/ruby/nes/cpu_bus.rb` | `Ruby::Nes::CpuBus` | CPU address decoding, RAM, open bus |
| `lib/ruby/nes/cpu.rb` | `Ruby::Nes::Cpu` | registers, `step`, interrupts |
| `lib/ruby/nes/cpu/` | `Ruby::Nes::Cpu::…` | instruction table, addressing modes |
| `lib/ruby/nes/ppu_bus.rb` | `Ruby::Nes::PpuBus` | PPU address decoding, VRAM, palette RAM |
| `lib/ruby/nes/ppu.rb`, `ppu/` | `Ruby::Nes::Ppu`, `Ruby::Nes::Ppu::…` | registers, timing, renderer pieces |
| `lib/ruby/nes/apu.rb`, `apu/` | `Ruby::Nes::Apu`, `Ruby::Nes::Apu::…` | channels, frame counter, mixer |
| `lib/ruby/nes/input/` | `Ruby::Nes::Input::Controller` | controllers |
| `lib/ruby/nes/frontends/` | `Ruby::Nes::Frontends::Base`, `::Headless`… | headless, raylib/sdl2 (later) |
| `lib/ruby/nes/debug/` | `Ruby::Nes::Debug::Tracer`, `::FrameDump`… | tooling off the hot path |
| `lib/ruby/nes/bits.rb` | `Ruby::Nes::Bits` | readable bit helpers for code off the hot path |
| `lib/ruby/nes/cli.rb` | — | command line (plan 18) |
| `spec/support/test_roms.rb`, `spec/support/test_roms/` | `TestRoms`, `TestRoms::Manifest`, `::Fetcher`… | test ROM harness (plan 02): test tooling, not shipped in the gem |

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
- Memory is an `Array` of Integer (decision 2) until plan 10 says otherwise.

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
expands its own. Standard computing acronyms used by the tooling (URL, HTTP, YAML, SHA-256, SSL) are allowed on the
same terms (decision 5): each is expanded in [`GLOSSARY.md`](GLOSSARY.md#computing-terms). Anything else is spelled
out.

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
| 2 | 2026-11-17 | Memory container: `Array` of Integer | Most readable; no evidence yet for the alternatives | Plan 10 (Array vs String vs `IO::Buffer`) |
| 3 | 2026-11-17 | Hot paths write bit operations inline with named constants and `# glossary:` tags; flag tests always use `anybits?`/`nobits?` | No method call per cycle, meaning still one lookup away; RuboCop enforces the predicates | Plan 10 (`Bits` helpers vs inline operators) |
| 4 | 2026-11-17 | Hardware acronyms kept in names, expanded in the glossary | They match the reference documentation readers search | — |
| 5 | 2026-11-17 | Standard computing acronyms (URL, HTTP, YAML, SHA-256, SSL) allowed in tooling names, expanded in the glossary | They are what the libraries and protocols call them; spelling them out (`address` for URL) would clash with emulator terms | — |
