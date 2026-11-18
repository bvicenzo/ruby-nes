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

Out: changing behaviour. Every optimisation keeps the whole suite (including test ROMs) green.

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

## References

- YJIT documentation (stats, side exits) — https://docs.ruby-lang.org/en/master/yjit/yjit_md.html
- ZJIT documentation — https://docs.ruby-lang.org/en/master/zjit_md.html
- vernier — https://github.com/jhawthorn/vernier
- stackprof — https://github.com/tmm1/stackprof
- Catch-up — https://www.nesdev.org/wiki/Catch-up
