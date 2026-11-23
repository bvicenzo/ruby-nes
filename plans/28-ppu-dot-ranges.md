# 28 — PPU dot ranges

**Status:** done (2026-11-22)

**Depends on:** 25

## Goal

Close the speed gap plan 25 left (milestone M7): run the PPU over a range of dots per call between the points where
something outside it can change its state, instead of one `Ppu#catch_up` iteration, one `FrameTiming#advance` and one
`Renderer#run_dot` per dot, while keeping the frame and audio digests of `rake bench:frames` unchanged.

## Context

Plan 25 measured Super Mario Bros. 3 in world 1-1 at 42.7 ms per frame under YJIT (23.4 fps) after its two kept
steps, from 70.3 ms. Its vernier profile (`rake bench:profile`) puts the loop around each dot (`Ppu#catch_up`,
`FrameTiming#advance`, `RenderSchedule#steps`, `Renderer#run_dot`) at about 26% of the frame, about 11 ms: a floor no
change inside a dot can lower. The budget is 16.6 ms; the CPU takes about 4 ms of it, the APU and audio about 6 ms
(`docs/benchmarks.md`, Findings, plan 25).

The [Catch-up](https://www.nesdev.org/wiki/Catch-up) page's recipe: run the least predictable component (the CPU) up
to the next time it could affect another, then run the others up to it. The PPU already has those sync points (every
PPU and APU register access, every mapper write, plan 21 decision 6), so between two of them nothing but the PPU's own
timeline changes its state, and a range can run in a tight loop: on dots 1-256 of a visible line, a tile of 8 dots is
4 fetches, 8 pixels and a reload.

What makes it more than a loop:

- MMC3's A12 watch (plan 21, decision 2) reads `Ppu#elapsed_dots` at every pattern fetch. A range must still tell the
  mapper the dot of each fetch, or the scanline IRQ moves.
- The frame timing's events (VBlank start and end, picture completed, the odd frame's skipped dot, the `$2002` read
  race) must land on their dot, and /NMI changes keep their CPU cycle (plan 12, decision 2).
- A range may start or stop inside a tile; the partial tile keeps the per-dot path.

## Scope

In:

- A sync deadline for `Console#run_frame`: the PPU is caught up only where it can affect the CPU, besides the register
  and mapper accesses that already sync it. Those points are its next /NMI change, the end of the frame and the
  earliest cycle the board could assert its IRQ.
- `Ppu#catch_up`, `Ppu::FrameTiming` and `Ppu::Renderer` restructured together, so a call runs a range of dots and
  whole tiles run as one fixed sequence. The dot of each fetch stays available to the mapper.
- Measured with `rake bench:frames` against plan 25's last numbers.

Out:

- Accuracy shortcuts (rendering ahead of the CPU, a whole scanline at once regardless of mid-line writes). Those stay
  for the user to decide with their measured gain (plan 25, decision 4).
- The APU and audio: it keeps its catch-up after every step. The DMC steals CPU cycles, so deferring it needs its own
  deadlines.
- The background fetch path and the items plan 25 left (its decision 9). They are the next candidates.

## Findings that reshaped the plan

The plan assumed that between two sync points the PPU already runs a long stretch. It does not. `Console#step`
catches the PPU up after every instruction, so each `catch_up` covers 6-21 dots. A prototype of the range loop with
that traffic gained nothing, and a whole-tile path almost never applied.

The [Catch-up](https://www.nesdev.org/wiki/Catch-up) recipe's missing half is to run the CPU up to the next time the
PPU *could* affect it. Besides register and mapper accesses, the PPU reaches the CPU in three ways, each predictable
with a conservative bound:

- the /NMI line, on dot 1 of scanlines 241 and 261;
- the end of the frame, which ends `run_frame`;
- MMC3's IRQ, through A12 rises.

Throwaway prototypes, A/B interleaved under YJIT on a noisy machine, with frame and audio digests identical to plan
25's in every variant:

| Variant | ms per frame |
|---|---|
| Plan 25's tree | ~46 |
| + sync deadline | ~43 |
| + ranges of dots | ~40 |
| + whole tiles, unrolled | ~34 |
| whole tiles as an inline pixel loop (`while` + `case`) instead | ~48 |

## Decisions

1. **Sync deadline in `Console#run_frame` only.** Each iteration steps the CPU, catches the PPU up only when
   `cpu.cycles >= ppu.sync_cycle`, then catches the APU up as today. `Console#step` keeps catching everything up
   after each step: the tracer and the nestest runner read the PPU's position after it. The test ROMs of the slow
   suite and the frontends use `run_frame`, so `ppu_vbl_nmi` and `cpu_interrupts_v2` check the new model's /NMI
   side. The suite's `mmc3_test_2` ROMs clock A12 through `$2006` and `$2007`, register accesses that catch the PPU
   up anyway. So a console example runs an MMC3 program whose IRQs come while it touches nothing, and checks that it
   takes each IRQ on the same instruction as when it is stepped.
2. **`Ppu#sync_cycle`** is the first CPU cycle at whose end the PPU must be caught up. It is the earlier of:
   - the cycle of the frame timing's next event: VBlank start or end, or the next frame's first dot, with the odd
     frame's skipped dot;
   - the board's earliest IRQ cycle.

   It is memoised and cleared by `catch_up`, `cpu_read`, `cpu_write` and `reset`: every write to a PPU or mapper
   register is preceded by a `catch_up`, so no change escapes it.

   Why no margin is needed: an event entered on elapsed dot D changes /NMI on cycle ⌊(D + 1) / 3⌋. A step starting
   before ⌊D / 3⌋ polls before that cycle ("the end of the second-to-last cycle", plan 22), so the deadline ⌊D / 3⌋ is
   enough. An A12 rise's IRQ is stamped with its M2 cycle ⌊D / 3⌋.
3. **MMC3's IRQ bound:** `IrqCounter#earliest_irq_cycle(cycle)`.
   - Disabled: never.
   - Enabled: `cycle + (clocks to the IRQ − 1) × 3`.
     - Clocks to the IRQ: the counter when above 0; otherwise 1 when the latch is 0, or the latch + 1.
     - The 3 is a derivation from the A12 filter ("a rising edge after the line has remained low for three falling
       edges of M2", https://www.nesdev.org/wiki/MMC3): two counted rises are at least 3 M2 cycles apart.

   `Mappers::Base#earliest_irq_cycle` answers never. `PpuBus` hands the question to its board, which already watches
   the PPU bus.
4. **The range loop lives in `Ppu`** (open decision 2), which owns the dot count and the frame timing.
   - Each iteration enters the next dot through `FrameTiming#advance`, with its events.
   - It runs the range up to the last quiet dot of the line through `Renderer#run_dots(scanline, first_dot,
     last_dot)`, then moves the frame timing there with `advance_to`.
   - The last quiet dot is:
     - dot 0 itself on scanlines 241 and 261, whose dot 1 tells the VBlank events;
     - 339 on the pre-render line of an odd frame with rendering enabled;
     - 340 otherwise.

   Rendering is sampled where the per-dot model samples it, at dot 339: a range only ends past it when no write could
   change it in between.
5. **The mapper learns each fetch's dot from a shared clock** (open decision 1), `Ppu::DotClock`, holding the elapsed
   dots.
   - The Ppu ticks it into each range and sets it to the range's last dot.
   - The renderer sets it to each dot with work before that dot's fetches.
   - `Ppu#elapsed_dots` reads it, so `Mmc3::A12Watcher` and the bus contract do not change.
6. **Whole tiles.** `RenderSchedule` marks dots 1, 9, …, 249 of the visible line with rendering enabled with a
   `WHOLE_TILE` flag.
   - When a range covers the tile's 8 dots, the renderer runs them as one fixed, unrolled sequence: the reload, 8
     pixels each followed by its shift, the four fetches on the tile's dots 0, 2, 4 and 6, coarse X on its last dot and
     Y on dot 256.
   - Split tiles, the pre-render line, dots 257-340 and the forced blank keep the per-dot path.
   - An inline pixel loop was measured slower than the per-dot path and is not kept.
7. **60 fps stays out of reach** (about 34 of 16.6 ms). The plan closes with the remaining gap quantified per
   component (`rake bench:profile`). The APU and the background fetch path are the next candidates.

## Tasks

- [x] Units, test first:
  - [x] `Mmc3::IrqCounter#earliest_irq_cycle`, with the board and bus hand-offs;
  - [x] `FrameTiming`'s next event, last quiet dot and `advance_to`;
  - [x] `DotClock`;
  - [x] `RenderSchedule#line` and `WHOLE_TILE`;
  - [x] `Renderer#run_dots`;
  - [x] `Ppu#catch_up` and `Ppu#sync_cycle`;
  - [x] `Console#run_frame`.
- [x] The whole suite and the test ROMs stay green.
- [x] Measure with `rake bench:frames`; profile with `rake bench:profile`; record the steps in `docs/benchmarks.md`.
- [x] `docs/architecture.md`:
  - [x] the clock model and its cost;
  - [x] the mapper interface;
  - [x] rendering;
  - [x] the decisions log.

## Acceptance criteria

- [x] `rake bench:frames` digests unchanged from plan 25 (f0903fbc59bf frame, 10369a5b40df audio).
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green.
- [x] The new frames per second recorded; either 60 fps under one configuration with the window's audio free of
      crackles, or the remaining gap quantified per component.

## What was done

- **Sync deadline.** `Console#run_frame` catches the PPU up from `Ppu#sync_cycle` on, about three times a frame
  instead of after every instruction. `Ppu#sync_cycle` is memoised and cleared by every catch-up, register access and
  reset. It takes the board's bound from `Mappers::Base#earliest_irq_cycle` through `PpuBus`, which for MMC3 is
  `Mmc3::IrqCounter#earliest_irq_cycle`.
- **Ranges and the dot clock.** `Ppu#catch_up` runs ranges within a scanline up to
  `FrameTiming#last_quiet_dot`, with `dots_to_next_event` and `advance_to` beside it. `Ppu::DotClock` is shared with
  the renderer, which sets it before every fetch.
- **Whole tiles.** `RenderSchedule#line` and `WHOLE_TILE`; `Renderer#run_dots` runs whole tiles unrolled.
- **Measured** (`rake bench:frames`):

  | Configuration | Plan 25's final | Now |
  |---|---|---|
  | interpreter | 5.2 fps | 7.0 fps |
  | yjit | 23.4 fps | 27.9 fps |
  | zjit | 15.4 fps | 19.4 fps |

  Interleaved under YJIT, 44.5 ms became 35.9 ms (-19%). Frame and audio digests are unchanged.
- **The gap left:** about 19 ms per frame under YJIT. Per component, in `docs/benchmarks.md`: pixel ~29%, APU and audio
  ~21%, fetches ~17%, the loops ~13%, sprites ~9%, CPU ~8%.
- **Docs.** `docs/architecture.md`: clock model step 7 and its cost, the mapper interface, rendering, the layout table
  and decisions 74-76.
- **Independent review.** No correctness bugs. Applied:
  - an MMC3 example comparing `run_frame` with stepping, since the suite's MMC3 ROMs clock A12 through registers;
  - value-based `sync_cycle` specs from a non-zero position;
  - a whole-tile reload example;
  - the clock set before the tile's nametable and attribute fetches too;
  - a frame-crossing example for `run_frame`;
  - fetch dots derived from `TILE_STEPS`;
  - naming and layout fixes.

  Not changed: a bound 5 cycles late still passes every example, since the MMC3 bound is far below the real IRQ
  timing on almost every scanline. The example catches a bound that is dropped.
- Slow suite: 2676 examples, 0 failures. The raylib window specs cannot run in this environment, as in plans 22-25.

## References

- Catch-up — https://www.nesdev.org/wiki/Catch-up
- PPU rendering — https://www.nesdev.org/wiki/PPU_rendering
- PPU frame timing — https://www.nesdev.org/wiki/PPU_frame_timing
- MMC3 (the A12 counter) — https://www.nesdev.org/wiki/MMC3
- CPU interrupts (the poll) — https://www.nesdev.org/wiki/CPU_interrupts
