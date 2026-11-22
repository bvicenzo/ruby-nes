# 25 — Performance pass

**Status:** done (2026-11-22)

**Depends on:** 21, 24

## Goal

Reach full speed (60 fps with audio) for SMB3 under the best JIT, or document precisely how far each configuration
gets and why. Milestone M7.

## Context

Plan 10 measured the CPU alone. A full frame adds ~89 000 PPU dots and ~29 800 APU ticks to ~29 800 CPU cycles, so
the PPU is the expected hot spot. Typical levers: avoid per-dot method calls where nothing observable happens (batch
idle dots, render a scanline at once when no register was written mid-line), table lookups instead of bit
arithmetic in loops, catch-up for the APU, fewer ivar reads in tight loops, and checking JIT side exits.

## Scope

In:

- `bench/frame.rb` and `rake bench:frames`: SMB3 headless for N frames with a scripted input, reporting fps per
  configuration (no JIT, YJIT, ZJIT) — appended to `docs/benchmarks.md`.
- Profiling with a sampling profiler (vernier or stackprof — check which supports Ruby 4.0.9) and JIT stats.
- Optimisations, one at a time, each measured and kept only if it pays.
- Plan 10's leads (`docs/benchmarks.md`, Findings): the `Bits` helpers cost nothing measurable under YJIT on the
  per-instruction path, so measure the whole hot path converted before narrowing the hot-path exception (decision 3);
  re-run the CPU variants (`rake bench:variants`, `bench/cpu_benchmark/variants/`) after the core changes. A frame
  benchmark can reuse `CpuBenchmark::Session`, `::Summary` and `::Report`.
- Hot-path micro-changes earlier plans left to plan 10, which did not measure them: moving the program counter's
  advance out of `immediate_address` and merging `Status#update_zero_and_negative` into one expression (plan 05), and
  a `BASE_CYCLES` array instead of `Opcodes::TABLE[opcode].cycles` per step (plan 06). Each can be a CPU variant.
- Plan 11's per-access lookups: `Cpu#step` asks the bus for stall cycles after every instruction, and `PpuBus` asks
  the mapper's `mirroring` and indexes a table on every nametable access. The stall query measured about −8% under
  YJIT on nestest (16.4 → 15.1 emulated MHz); a pending flag inside `CpuBus` did not help, the cost being the call
  per step. Candidate: a push model, where the DMA tells the CPU (a counter or flag the CPU owns, checked like the
  interrupt lines), at the price of wiring the bus to the CPU after both exist.

Out: changing behaviour. Every optimisation keeps the whole suite (including test ROMs) green.

From plan 12: the PPU advances one dot per method call (`Ppu::FrameTiming`), 89 342 calls per frame before plan 13
adds rendering; register accesses catch the PPU up mid-instruction, and the indexed addressing modes do their dummy
reads. Each is a candidate for measurement.

From plan 13: the background is rendered per dot (plan 13, decision 1): `Ppu::Renderer` (called `BackgroundRenderer`
until plan 14) runs a step table for every dot of the visible and pre-render scanlines. A scanline fast path when no
PPU register was written mid-line is the obvious candidate; the nestest golden frame digest guards it.

From plan 14: composing the sprites costs about 28% of the frame rate under YJIT on nestest (26.6 to 19.2 frames per
second; architecture decision 34): per pixel, `SpriteRenderer#pixel` (the line buffer and its visibility) and
`PriorityMultiplexer#palette_entry`, plus the sprite steps of dots 257-320. Candidates: skipping the sprite path on
lines whose buffer is empty, and inlining the visibility.

From plan 16: `Ppu::Picture#draw` ORs the emphasis bits into every pixel (one more operation per visible dot) and
swaps two buffers once per frame; the frontends' RGB conversion (`Frontends::Palette.rgb`, one `values_at` + `join`)
costs about 2.8 ms per frame. `Frontends::Headless` with an `InputScript` is the scripted runner `bench/frame.rb`
can drive.

From plan 22: the APU is caught up one CPU cycle per loop iteration (`Apu#catch_up`, decision 3) after every step and
before every APU register access, the frame counter every cycle and the pulse timers every other one; the IRQ line and
the NMI edge carry cycle stamps, and taken branches and `CLI`/`SEI`/`PLP` tell the interrupt lines about their poll.
Candidates: advancing the frame counter straight to its next step instead of cycle by cycle, and measuring the
per-instruction cost of the poll bookkeeping.

From plan 23: the catch-up also ticks the triangle timer every CPU cycle and the noise and DMC timers every other one,
and `Apu#output` mixes the five channels through two constant tables on demand. The DMC halts the CPU through
`Cpu#halt(stall_cycles)` (a push, decision 1); OAM DMA still pulls through `CpuBus#take_stall_cycles` after every step
(architecture decision 20, measured at about −8% under YJIT): moving it to `Cpu#halt` removes that query, but must keep
`cpu_interrupts_v2/4-irq_and_dma` passing (plan 22, decision 5). Candidates: skipping a channel's timer while its
output cannot change (a halted triangle, a silent DMC with an empty buffer). Left by plan 23's review: `Apu::Dmc`
keeps the cycle `tick_timer` was given in an instance variable so the generic `Timer` → `step` call can pass it to the
output unit; revisit it if the timer interface changes.

From plan 24: with audio on, `Apu#catch_up` mixes the five channels every CPU cycle for the box resampler
(`@resampler&.add(output)`); measured before plan 24 at about −9% on SMB3 under YJIT (16.1 → 14.7 fps). Candidates:
remixing only when a channel's output changes, or averaging per APU cycle (an accuracy shortcut for the user to
decide). The window paces by audio (`Frontends::AudioPacing`); below full speed the music has gaps of silence (plan 24,
decision 2), so the crackle-free check is this plan's (plan 24, decision 3).

## Measurements at the start (plan review, 2026-11-22)

Super Mario Bros. 3 in world 1-1, audio at 48 kHz, Intel Core i5-8257U, measured in the session that refined this
plan (scripts in the scratch directory, not committed):

| Configuration | ms per frame | fps |
|---|---|---|
| YJIT, audio | 65-68 | ~14 |
| YJIT, no audio | 62 | ~16 |
| ZJIT, audio | 69 | ~14 |
| YJIT, `Renderer#run_dot` stubbed out | 11 | ~89 |

- **The per-dot `Ppu::Renderer` is about 83% of the frame.** The CPU, the APU, the PPU's frame timing and the audio
  fit in about 11 ms, inside the 16.6 ms budget.
- **The cost is the number of calls, not one collaborator.** Stubbing `Picture#draw`, the sprites' pixel, the
  priority multiplexer, the background's pixel or the fetches, one at a time, saves 1-4 ms each. A TracePoint count
  gives about 100 calls per dot (`Renderer#run_dot`, its four private methods, about ten collaborators and about 15
  `anybits?`), about 9 million per frame.
- **`anybits?` costs about 9 ns more than `(value & FLAG) != 0`** under YJIT and ZJIT (a loop of one test: 11.6 against
  2.5 ns per iteration under YJIT): the operator is compiled inline, the predicate is a C call. Replacing only the
  renderer's flag tests took the frame from 68.3 to 58.3 ms (-15%).
- **A Ruby method call costs about 5 ns under YJIT**, two to three times an inline operator. This settles plan 10's
  lead on the `Bits` helpers (decision 5 below).
- **Running a range of dots at once is exact.** The catch-up already brings the PPU up to date before every access to
  a PPU or APU register and every mapper write (plan 21, decision 6), so running the whole range of one `catch_up` in
  one go gives the same result dot by dot, as long as the fetches still go through `PpuBus` (MMC3's A12 watch sees
  them) and the frame timing's events (VBlank, picture completed) land on their dot.
- Outside the core, the frontend's RGB conversion (`Frontends::Palette.rgb`) costs about 2.8 ms per frame (plan 16),
  17% of the window's budget.

## Decisions

1. **Flag tests on hot paths use the operator:** `(steps & FLAG) != 0 # glossary: flag-set`, and `== 0` tagged
   `flag-clear`, both new glossary entries. `Style/BitwisePredicate` is disabled only for the directories that hold the
   per-dot, per-cycle and per-instruction code (`apu`, `cpu`, `input`, `mappers`, `ppu`), listed in `.rubocop.yml`; off
   hot paths `anybits?`/`allbits?`/`nobits?` stay mandatory. Reason: the measurement above (-15% from the renderer's
   tests alone). `docs/architecture.md` (Readability, exception 2, and the Decisions log) records the new rule.
2. **Benchmark workload:** Super Mario Bros. 3 (`roms/smb3.nes`, a local ROM) driven by the input script of the
   console spec, with audio at 48 kHz, drained every frame as the window does. It warms up to frame 1200 (inside
   world 1-1) and measures 5 runs of 60 consecutive frames: median and spread in frames per second. Reason: the
   gameplay exercises scrolling, sprites and the status bar split by MMC3's IRQ; the title screen does not.
3. **Comparison: trees A/B, guarded by digests.** `rake bench:frames` measures the working tree under the three
   configurations; each optimisation is compared with the commit before it (a git worktree in the scratch directory),
   alternating rounds, as plans 19-21 did. Each run prints the SHA-256 of the last frame and of the measured audio
   samples, so a change that alters the output shows at once. Reason: the big changes restructure the renderer,
   which a variant file reopening classes cannot express.
4. **Exact optimisations first.** An optimisation is kept only if the frame and audio digests are unchanged and the
   whole suite, test ROMs included, stays green. An accuracy shortcut (for example averaging the audio per APU
   cycle) is proposed only if the target is still out of reach, each with its measured gain and the tests it puts at
   risk, and the user decides then.
5. **Plan 10's `Bits` helpers lead (decision 3) is closed** by the call cost measured above: converting the hot path
   to method calls can only slow it down. No full-conversion variant is built.
6. **Profiler: vernier 1.12.0**, which builds on Ruby 4.0.9, in the Gemfile's development group with
   `require: false`.
7. **The renderer becomes a per-dot pipeline** (the user's choice over a moderate consolidation): `Ppu::Renderer` owns
   the background shift registers (`BackgroundShifters` is folded in), both layers' visibility, and the composition of
   each pixel; the priority multiplexer and the sprite 0 hit are asked only where both layers are opaque; the sprite
   renderer keeps the evaluation and the fetches, and hands its line's entries over as an array; the picture reads
   palette RAM without the PPU bus. Still one `run_dot` per dot, so `@dots` is right at every fetch MMC3's A12 watch
   reads. A throwaway prototype measured -20% to -30% of the frame (about 44 ms) with identical digests; the
   estimate made before it (48-60 fps) was wrong, since the loop around each dot alone is about 23% of the frame.
8. **M7 closes as a quantified gap** unless the remaining items get closer than expected: after the pipeline, the rest
   of the list (fetches, APU, sprite steps, OAM DMA, CPU, frontend), each measured. Running ranges of dots per call
   between the sync points (exact, but `Ppu#catch_up`, `FrameTiming` and `Renderer` restructured together so the mapper
   still learns each fetch's dot) is left to a new plan: plan 28.
9. **The rest of the list is not done in this plan** (the user's instruction to finish with my recommendations). The
   final profile (`rake bench:profile`, vernier, 200 frames) puts the loop around each dot at about 26% of the frame,
   the background fetches at about 19%, the pixel composition at about 17%, the APU and audio at about 14%, the CPU at
   about 9% and the sprite steps at about 7%. Each remaining item reaches a part of one of those: the APU items a few
   percent each (14% in all, spread over about ten methods); OAM DMA through `Cpu#halt`, about 8% of the CPU alone in
   plan 11, so under 1% of a frame; the CPU micro-changes of plans 05 and 06, a fraction of the CPU's 9%; the
   frontend's `Palette.rgb`, whose alternatives plan 16 measured (the best saves 0.6 ms, under YJIT only). None changes
   the conclusion that the loop around each dot is a floor above the budget, so plan 28 takes the ranges of dots first
   and keeps these as candidates.

## Tasks

- [x] Frame benchmark (`bench/frame.rb`, `bench/frame_benchmark/`, specs in `spec/frame_benchmark/`), reusing the
      shape of `CpuBenchmark` (one process per configuration, JSON out, Markdown appended to `docs/benchmarks.md`):
      `Options` (`--rom`, `--warm-up-frames` 1200, `--frames` per run 60, `--runs` 5), `Workload` (a console with
      audio and the input script; untimed warm-up, timed runs, the last frame's and the audio's digests),
      `Summary` (median fps, ms per frame, spread), `Report`, `CommandLine`, and `rake bench:frames`, which stops
      with a clear message without the local ROM. The input script moves from the console spec to a shared fixture
      (`spec/fixtures/smb3_world_1_1.yml`) read by the spec and the benchmark.
- [x] Baseline numbers for the three configurations.
- [x] Profiler in the Gemfile and `rake bench:profile` (the same workload, its output in `tmp/`); the top costs per
      component (CPU, PPU timing, renderer, APU, audio, frontend) in `docs/benchmarks.md`.
- [x] Iterate, in order of expected gain: hypothesis, change, A/B measure with identical digests, keep or revert;
      log each step in `docs/benchmarks.md`. A change of structure only is the refactor step of TDD, guarded by the
      existing specs; a new unit or contract goes through `specify-behavior`, `write-tests`, red, green.
  - [x] Flag tests with the operator on hot paths (decision 1): -23% of the frame under YJIT.
  - [x] The renderer as a per-dot pipeline (decision 7): a further -19% under YJIT.
  - [x] Grouping `run_dot`'s flag tests by stage: reverted, no gain in a prototype (52.2 → 55.4 ms, noise).
  - [ ] Not done (decision 9). APU: the frame counter jumping to its next step; timers whose output cannot change
        (a halted triangle, a silent DMC) not ticked; remixing only when a channel's output changes (exact if the
        audio digest holds).
  - [ ] Not done (decision 9). OAM DMA through `Cpu#halt` (a push), removing `CpuBus#take_stall_cycles` from every
        step, with `cpu_interrupts_v2/4-irq_and_dma` passing.
  - [ ] Not done (decision 9). The CPU micro-changes of plans 05 and 06 (`BASE_CYCLES` array, the program counter's
        advance out of `immediate_address`, `update_zero_and_negative` in one expression), also measured with
        `rake bench:variants`.
  - [ ] Not done (decision 9). Frontend: `Palette.rgb` from a prebuilt table of bytes per pixel, without
        `values_at` + `join` per frame.
- [x] After each kept optimisation: `rake bench:frames` and `SLOW=1 RUBYOPT=--yjit bundle exec rake`.
- [x] Re-evaluate the default JIT with whole frames (YJIT stays); re-run `rake bench:cpu` and `rake bench:variants`
      (plan 10).
- [x] At full speed, play world 1-1 in the window and listen for crackles; below it, quantify the gap per component
      and propose the accuracy shortcuts with their gains. Below it: the gap is in `docs/benchmarks.md` (Findings,
      plan 25); no accuracy shortcut is proposed yet, since the exact ranges of dots (plan 28) come first.

## Acceptance criteria

- [x] `rake bench:frames` measures Super Mario Bros. 3 (world 1-1 gameplay, with audio) under no JIT, YJIT and ZJIT.
- [x] `docs/benchmarks.md` has baseline and final fps for each configuration on the same machine.
- [x] Every kept optimisation has its measured gain recorded; every reverted one has the reason.
- [x] Every exact optimisation keeps the benchmark's frame and audio digests; no accuracy shortcut without the user's
      decision.
- [x] Full test suite and test ROM results unchanged or improved (`SLOW=1 RUBYOPT=--yjit bundle exec rake` green).
- [x] Either SMB3 runs at 60 fps under at least one configuration, or the remaining gap is quantified per component.
- [x] The crackle-free check at full speed (moved from plan 24, decision 3) is handed to plan 28, which carries it in
      its acceptance criteria: SMB3 does not reach full speed in this plan (decision 8).
- [x] `docs/architecture.md` (the flag rule on hot paths, the renderer as a per-dot pipeline) and `docs/GLOSSARY.md`
      updated.

## What was done

- The frame benchmark: `FrameBenchmark::{Sample, Workload, Session, Summary, Options, CommandLine, Report}`,
  `bench/frame.rb` and `rake bench:frames` (Super Mario Bros. 3 in world 1-1, audio on, the last frame's and the
  audio's SHA-256 per run); `BenchmarkStatistics` (median, spread) shared with `CpuBenchmark::Summary`; the console
  spec's input script moved to `spec/fixtures/smb3_world_1_1.yml`. vernier 1.12.0 and `rake bench:profile`.
- Step 1, flag tests inline on hot paths (decision 1, architecture decision 72; glossary `flag-set`, `flag-clear`,
  `all-flags-set`; `Style/BitwisePredicate` off in `apu`, `cpu`, `input`, `mappers`, `ppu`): -23% of the frame under
  YJIT. Step 2, the renderer as a per-dot pipeline (decision 7, architecture decision 73): `BackgroundShifters` folded
  into `Ppu::Renderer`, which composes each pixel in one `draw`, reads `SpriteRenderer#line_entries` and both layers'
  `LayerVisibility#first_visible_column`, and asks `PriorityMultiplexer` (now "both opaque" only) where the layers
  overlap; `Picture` reads `PpuBus#palette_ram` directly; `Ppu` tells the renderer the sprite PPUMASK bits. A further
  -19%. Every run kept the baseline's digests.
- Final numbers (`docs/benchmarks.md`, Findings): 4.3 → 5.2 fps without a JIT, 14.2 → 23.4 under YJIT, 12.7 → 15.4
  under ZJIT; YJIT stays the default. The 26 ms gap under YJIT is quantified per component; the loop around each dot
  (about 11 ms) is a floor above the budget, so plan 28 (PPU dot ranges) is added. `rake bench:cpu` measures the APU
  too since plan 22 (about 60% of its time), which explains its 4.3 MHz.
- Not done, with their measured shares (decision 9): the APU, OAM DMA, CPU micro-change and frontend items.
- Independent review: applied the multiplexer's narrowed contract, `Renderer#background_left_columns_shown=`,
  `Workload.from_files` and the shared report helper in `rakelib/bench.rake`, `fdiv` in `BenchmarkStatistics` (whole
  numbers in its spec), the crackle criterion handed to plan 28, the cop's scope worded as directories, plan 28's
  numbers, the references, line breaks. Not applied: hoisting the renderer spec's subject (the visibilities are
  constructor premises per context), removing redundant `palette_ram: nil` stubs, sharing the pixel pack format with
  `Frontends::Headless` (the benchmark would load the headless frontend). CLAUDE.md's readability summary still says
  "flag tests always with `anybits?`"; it is the user's file, left for the user to update.
- The raylib window specs crash this environment's Ruby when its window cannot open (as in plans 22-24); they passed
  once outside the sandbox during this plan (9 examples). The suite ran with `--tag '~frontend_library'`:
  `SLOW=1 RUBYOPT=--yjit`, 2627 examples, 0 failures.

## References

- YJIT documentation (stats, side exits) — https://docs.ruby-lang.org/en/master/yjit/yjit_md.html
- ZJIT documentation — https://docs.ruby-lang.org/en/master/zjit_md.html
- vernier — https://github.com/jhawthorn/vernier
- stackprof — https://github.com/tmm1/stackprof
- Catch-up — https://www.nesdev.org/wiki/Catch-up
- PPU rendering (shift registers, the priority multiplexer) — https://www.nesdev.org/wiki/PPU_rendering
- PPU palettes (transparent pixels, palette RAM) — https://www.nesdev.org/wiki/PPU_palettes
- PPU sprite priority — https://www.nesdev.org/wiki/PPU_sprite_priority
- Cycle reference chart (the NTSC frame rate, 60.0988 Hz) — https://www.nesdev.org/wiki/Cycle_reference_chart
