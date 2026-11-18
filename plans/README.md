# ruby-nes plans

The roadmap from an empty gem to Super Mario Bros. 3 running with sound, plus the performance experiments that are the
point of the study. Plans are executed in order; each one states what it depends on.

Conventions (see also `CLAUDE.md`):

- Plans are written in English; they are discussed with the user in Portuguese.
- Every unit is built test-first: `specify-behavior` produces the spec tree, `write-tests` fills it.
- Hardware behaviour asserted in specs must be backed by the plan's references, never by memory.
- A plan is **done** only when every acceptance criterion is checked. Update the status column here.
- Each plan has an **Open decisions** section: settle those with the user when the plan starts.

## Milestones

| Milestone | Reached after | What it proves |
|---|---|---|
| M1 — CPU correct | 09 | nestest.log matches line by line (blargg instruction tests follow in plan 12) |
| M2 — JIT baseline | 10 | interpreter vs YJIT vs ZJIT measured on a CPU-only workload |
| M3 — First picture | 13 | a test ROM's background renders headless to an image |
| M4 — First game | 18 | an NROM game is playable in a window |
| M5 — Super Mario Bros. 3 | 21 | SMB3 plays world 1-1 with a stable status bar |
| M6 — Sound | 24 | SMB3 plays with audio |
| M7 — Fast enough | 25 | full speed (60 fps) or a documented gap, per JIT |
| M8 — AOT experiment | 26 | Spinel findings documented |

## Index

| # | Plan | Depends on | Status |
|---|---|---|---|
| 00 | [Project setup](00-project-setup.md) | — | done |
| 01 | [Architecture and conventions](01-architecture-and-conventions.md) | 00 | done |
| 02 | [Test ROM harness](02-test-rom-harness.md) | 00 | done |
| 03 | [iNES cartridge loader](03-ines-cartridge-loader.md) | 01 | done |
| 04 | [CPU bus, mapper interface and NROM](04-cpu-bus-mapper-interface-nrom.md) | 03 | done |
| 05 | [CPU registers and addressing modes](05-cpu-registers-and-addressing-modes.md) | 04 | done |
| 06 | [CPU official instructions](06-cpu-official-instructions.md) | 05 | done |
| 07 | [CPU interrupts and power-up](07-cpu-interrupts-and-power-up.md) | 06 | done |
| 08 | [nestest trace (official opcodes)](08-nestest-trace-official.md) | 02, 07 | done |
| 09 | [CPU unofficial opcodes and blargg CPU tests](09-cpu-unofficial-opcodes.md) | 08 | todo |
| 10 | [JIT benchmark: interpreter vs YJIT vs ZJIT](10-jit-benchmark.md) | 09 | todo |
| 11 | [PPU registers and VRAM](11-ppu-registers-and-vram.md) | 04 | todo |
| 12 | [PPU timing, VBlank/NMI and the console loop](12-ppu-timing-vblank-nmi.md) | 07, 11 | todo |
| 13 | [PPU background rendering](13-ppu-background-rendering.md) | 12 | todo |
| 14 | [PPU sprites](14-ppu-sprites.md) | 13 | todo |
| 15 | [Controllers](15-controllers.md) | 04 | todo |
| 16 | [Frontend interface and headless backend](16-frontend-interface-headless.md) | 13 | todo |
| 17 | [Backend comparison: raylib vs SDL2](17-backend-comparison-raylib-sdl2.md) | 14, 15, 16 | todo |
| 18 | [Interactive frontend and CLI](18-interactive-frontend-cli.md) | 17 | todo |
| 19 | [Simple mappers: UxROM, CNROM, AxROM](19-simple-mappers-uxrom-cnrom-axrom.md) | 04 | todo |
| 20 | [Mapper MMC1](20-mapper-mmc1.md) | 19 | todo |
| 21 | [Mapper MMC3 and Super Mario Bros. 3](21-mapper-mmc3-smb3.md) | 14, 18, 20 | todo |
| 22 | [APU: pulse channels and frame counter](22-apu-pulse-frame-counter.md) | 12 | todo |
| 23 | [APU: triangle, noise, DMC and mixer](23-apu-triangle-noise-dmc-mixer.md) | 22 | todo |
| 24 | [Audio output and synchronisation](24-audio-output-sync.md) | 18, 23 | todo |
| 25 | [Performance pass](25-performance-pass.md) | 21, 24 | todo |
| 26 | [Spinel AOT experiment](26-spinel-experiment.md) | 10 (minimum), 25 (full) | todo |

Plans 11, 15 and 19 only depend on the bus, so they can be pulled forward if the CPU work gets tiring.

## Backlog (not planned)

- Battery-backed PRG RAM persistence (SMB3 has none; Zelda/Final Fantasy need it).
- Save states.
- MMC5, MMC2/MMC4, NES 2.0 extended fields beyond detection.
- PAL timing.
- Ractors — discarded: CPU, PPU and APU are coupled at cycle granularity, so message passing would cost more than it
  saves. Revisit only if profiling finds a separable stage (e.g. audio presentation).

## General references

- NESdev Wiki — https://www.nesdev.org/wiki/Nesdev_Wiki
- NES reference guide (index of hardware pages) — https://www.nesdev.org/wiki/NES_reference_guide
- Emulator tests (test ROM catalogue) — https://www.nesdev.org/wiki/Emulator_tests
- Test ROM collection — https://github.com/christopherpow/nes-test-roms
- Mesen source (accurate, readable reference emulator) — https://github.com/SourMesen/Mesen2
