# 01 — Architecture and conventions

**Depends on:** 00

## Goal

Fix, in writing, the component layout, the clock model and the hot-path coding rules before any emulation code exists,
so every later plan builds on the same shape. Output is a design document plus empty namespaces — no behaviour.

## Context

The NES (NTSC) is a set of chips driven by one master clock:

- CPU (Ricoh 2A03: a 6502 without decimal mode, plus the APU) at ~1.789773 MHz.
- PPU (2C02) at exactly 3 dots per CPU cycle; a frame is 262 scanlines × 341 dots (one dot shorter on odd frames
  with rendering on), ~29780.5 CPU cycles, ~60.0988 frames per second.
- The cartridge (mapper) sits on both the CPU bus and the PPU bus.

Components talk only through buses: the CPU never calls the PPU directly, it reads/writes `$2000-$2007`.

## Scope

In:

- `docs/architecture.md` with the component diagram, buses, clock model and the rules below.
- Empty module skeletons (`Ruby::Nes::Cpu`, `Ppu`, `Apu`, `Cartridge`, `Mappers`, `Input`, `Frontends`, `Console`)
  only if useful for requires; no logic.

Out: any behaviour (comes with the plans that specify it).

## Design to document

1. **Layout** (proposed):

   ```text
   lib/ruby/nes/
     console.rb           # wires components, runs the clock
     cartridge/           # iNES parsing, Cartridge value
     mappers/             # Mapper base + one file per mapper
     cpu/                 # Cpu, instruction table, CpuBus
     ppu/                 # Ppu, PpuBus, renderer pieces
     apu/                 # channels, frame counter, mixer
     input/               # controllers
     frontends/           # headless, raylib/sdl2 (later)
     cli.rb
   ```

2. **Loading:** explicit `require_relative`, no autoloader. Keeps load order obvious and the code friendly to an AOT
   compiler (plan 26).

3. **Clock model — open decision** (see below). Recommended start: *instruction-level catch-up*. `Cpu#step` executes
   one instruction and returns the cycles spent; `Console` then advances the PPU `cycles * 3` dots and the APU
   `cycles` ticks. Upgrade path if test ROMs demand it (plans 12, 21): tick the PPU on every CPU bus access instead.

4. **Hot-path rules** (CPU step, PPU dot, APU tick):
   - Integers only; mask explicitly (`& 0xFF`, `& 0xFFFF`).
   - Preallocated buffers (RAM, VRAM, OAM, frame buffer); no allocation per cycle or per instruction.
   - No `define_method`/`method_missing`/`send` on hot paths; plain methods and constant tables.
   - No exceptions for control flow.
   - Value objects (`Data.define`) are fine for configuration (iNES header), never per cycle.

5. **Frame buffer contract:** the PPU writes palette indices (0–63, plus emphasis bits later) into a preallocated
   256×240 buffer; converting to RGB is the frontend's job. This keeps the core free of graphics libraries.

6. **No threads, no Ractors** in the core.

## Open decisions

- Clock model: instruction-level catch-up (simpler, faster in Ruby) vs per-bus-access ticking (more accurate, more
  calls per instruction). Recommendation: catch-up first, measured against test ROMs.
- Memory container for RAM/VRAM: `Array` of Integer vs binary `String` with `getbyte`/`setbyte` vs `IO::Buffer`.
  Recommendation: `Array` now, benchmarked in plan 10.

## Tasks

- [ ] Write `docs/architecture.md` (diagram, buses, clock model, hot-path rules, frame buffer contract).
- [ ] Record the outcome of both open decisions in the document.
- [ ] Link `docs/architecture.md` from `CLAUDE.md`.

## Acceptance criteria

- [ ] `docs/architecture.md` exists and covers: layout, buses with address ranges, clock ratios with sources, the
      chosen clock model and its upgrade path, hot-path rules, frame buffer contract.
- [ ] Both open decisions are recorded with the reason.
- [ ] `bundle exec rake` still green.

## References

- CPU — https://www.nesdev.org/wiki/CPU
- CPU memory map — https://www.nesdev.org/wiki/CPU_memory_map
- PPU memory map — https://www.nesdev.org/wiki/PPU_memory_map
- Cycle reference chart (clock rates, frame length) — https://www.nesdev.org/wiki/Cycle_reference_chart
- PPU frame timing — https://www.nesdev.org/wiki/PPU_frame_timing
- Catch-up (emulation technique) — https://www.nesdev.org/wiki/Catch-up
- Ruby `Data` — https://docs.ruby-lang.org/en/master/Data.html
- Ruby `IO::Buffer` — https://docs.ruby-lang.org/en/master/IO/Buffer.html
