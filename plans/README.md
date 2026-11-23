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
| 09 | [CPU unofficial opcodes](09-cpu-unofficial-opcodes.md) | 08 | done |
| 10 | [JIT benchmark: interpreter vs YJIT vs ZJIT](10-jit-benchmark.md) | 09 | done |
| 11 | [PPU registers and VRAM](11-ppu-registers-and-vram.md) | 04 | done |
| 12 | [PPU timing, VBlank/NMI and the console loop](12-ppu-timing-vblank-nmi.md) | 07, 11 | done |
| 13 | [PPU background rendering](13-ppu-background-rendering.md) | 12 | done |
| 14 | [PPU sprites](14-ppu-sprites.md) | 13 | done |
| 15 | [Controllers](15-controllers.md) | 04 | done |
| 16 | [Frontend interface and headless backend](16-frontend-interface-headless.md) | 13 | done |
| 17 | [Backend comparison: raylib vs SDL3](17-backend-comparison-raylib-sdl3.md) | 14, 15, 16 | done |
| 18 | [Interactive frontend and CLI](18-interactive-frontend-cli.md) | 17 | done |
| 19 | [Simple mappers: UxROM, CNROM, AxROM](19-simple-mappers-uxrom-cnrom-axrom.md) | 04 | done |
| 20 | [Mapper MMC1](20-mapper-mmc1.md) | 19 | done |
| 21 | [Mapper MMC3 and Super Mario Bros. 3](21-mapper-mmc3-smb3.md) | 14, 18, 20 | done |
| 22 | [APU: pulse channels and frame counter](22-apu-pulse-frame-counter.md) | 12 | done |
| 23 | [APU: triangle, noise, DMC and mixer](23-apu-triangle-noise-dmc-mixer.md) | 22 | done |
| 24 | [Audio output and synchronisation](24-audio-output-sync.md) | 18, 23 | done |
| 25 | [Performance pass](25-performance-pass.md) | 21, 24 | done |
| 26 | [Spinel AOT experiment](26-spinel-experiment.md) | 10 (minimum), 25 (full) | todo |
| 27 | [Horizontal edge crop](27-horizontal-edge-crop.md) | 18 | todo |
| 28 | [PPU dot ranges](28-ppu-dot-ranges.md) | 25 | done |
| 29 | [APU sync deadline and runs of cycles](29-apu-sync-deadline-and-runs.md) | 28 | done |
| 30 | [Background pipeline per tile](30-background-pipeline-per-tile.md) | 28 | done |
| 31 | [Sprites and the horizontal blank](31-sprites-and-horizontal-blank.md) | 30 | done |
| 32 | [Window presentation](32-window-presentation.md) | 31 | done |
| 33 | [Super Pitfall's emulation cost](33-super-pitfall-emulation-cost.md) | 32 | todo |

Plans 11, 15 and 19 only depend on the bus, so they can be pulled forward if the CPU work gets tiring.

Plans 29-31 go after the gap M7 left (27.9 fps under YJIT after plan 28), each exact: the `rake bench:frames` digests
stay unchanged. They grouped plan 28's per-component profile by what changes together: the APU, the background's
pixel, fetch and loop, the sprites and dots 257-340. Each starts by profiling again, and the series stops at the plan
that reaches 60 fps with crackle-free audio. Accuracy shortcuts enter only as an optional fast mode, with the exact
model as the default (architecture decision 77).

Plan 31 brought the emulation to 61.5 fps under YJIT; the window still showed 50-52 fps, its presentation (turning a
frame into RGB, about 2.6 ms) being the gap. Plan 32 moved the palette lookup to the GPU (about 0.8 ms a frame), and
Super Mario Bros. 3 plays at about 60 fps with crackle-free audio: M7 closed. Super Pitfall (UxROM, CHR RAM) still
drops to 48-53 fps in play, its emulation about 12% heavier; plan 33 profiles and cuts it, exactly as plans 29-31.

## Backlog (not planned)

- Battery-backed PRG RAM persistence (SMB3 has none; Zelda/Final Fantasy need it).
- Save states.
- A TV-like border in the backdrop colour around the picture (plan 27, decision 3), which needs the backdrop colour
  of every frame from the PPU.
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
