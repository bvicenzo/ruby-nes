# 28 — PPU dot ranges

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

In: `Ppu#catch_up`, `Ppu::FrameTiming` and `Ppu::Renderer` restructured together so a call runs a range of dots,
with the dot of each fetch available to the mapper; measured with `rake bench:frames` against plan 25's last numbers.

Out: accuracy shortcuts (rendering ahead of the CPU, a whole scanline at once regardless of mid-line writes); those
stay for the user to decide with their measured gain (plan 25, decision 4). The APU and audio (about 14% of the frame in
plan 25's profile), the background fetch path (about 19%) and the items plan 25 left (its decision 9) are candidates if
the ranges alone do not reach the budget.

## Open decisions

- How the mapper learns each fetch's dot inside a range: the PPU advancing its elapsed dots before each fetch, or the
  fetch carrying the dot.
- Where the range loop lives: in `Ppu` (which owns the dot count) or in the renderer, told the elapsed dots.

## Tasks

- [ ] Design the range model with its spec tree and present it before the code.
- [ ] Implement it unit by unit; the whole suite and the test ROMs stay green.
- [ ] Measure with `rake bench:frames`; profile with `rake bench:profile`; record the step in `docs/benchmarks.md`.

## Acceptance criteria

- [ ] `rake bench:frames` digests unchanged from plan 25.
- [ ] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green.
- [ ] The new frames per second recorded; either 60 fps under one configuration with the window's audio free of
      crackles, or the remaining gap quantified per component.

## References

- Catch-up — https://www.nesdev.org/wiki/Catch-up
- PPU rendering — https://www.nesdev.org/wiki/PPU_rendering
- PPU frame timing — https://www.nesdev.org/wiki/PPU_frame_timing
- MMC3 (the A12 counter) — https://www.nesdev.org/wiki/MMC3
