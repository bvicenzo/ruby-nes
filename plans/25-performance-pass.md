# 25 — Performance pass

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

## Open decisions

- Which accuracy shortcuts are acceptable (e.g. scanline-based fast path, APU catch-up)? Each one is proposed with its
  measured gain and the tests it would put at risk, and the user decides.

## Tasks

- [ ] Frame benchmark and baseline numbers for the three configurations.
- [ ] Profile; list the top costs per component.
- [ ] Iterate: hypothesis → change → measure → keep or revert; log each step in `docs/benchmarks.md`.
- [ ] Re-evaluate the default JIT.

## Acceptance criteria

- [ ] `docs/benchmarks.md` has baseline and final fps for each configuration on the same machine.
- [ ] Every kept optimisation has its measured gain recorded; every reverted one has the reason.
- [ ] Full test suite and test ROM results unchanged (or improved).
- [ ] Either SMB3 runs at 60 fps under at least one configuration, or the remaining gap is quantified per component.
- [ ] When SMB3 runs at full speed, the window plays its music and effects without crackles (moved from plan 24,
      decision 3).

## References

- YJIT documentation (stats, side exits) — https://docs.ruby-lang.org/en/master/yjit/yjit_md.html
- ZJIT documentation — https://docs.ruby-lang.org/en/master/zjit_md.html
- vernier — https://github.com/jhawthorn/vernier
- stackprof — https://github.com/tmm1/stackprof
- Catch-up — https://www.nesdev.org/wiki/Catch-up
