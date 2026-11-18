# 10 — JIT benchmark: interpreter vs YJIT vs ZJIT

**Depends on:** 09

## Goal

Measure how fast the CPU core runs on Ruby 4.0.9 without a JIT, with YJIT and with ZJIT, using a reproducible
harness, and use it to settle the hot-path open decisions left by plans 01, 05 and 06. Milestone M2.

## Context

The real CPU runs ~1.789773 MHz; a frame is ~29 780 CPU cycles. The CPU is only part of the work (the PPU does three
dots per CPU cycle and usually dominates), so this benchmark is an upper bound on what a full frame will cost, not a
verdict.

Ruby 4.0.9 exposes `--yjit` and `--zjit` (both disabled by default), with `--yjit-stats` / `--zjit-stats` for
compilation statistics. ZJIT is the newer method-based JIT; whether it beats YJIT on this workload is what this plan
measures, not what it assumes.

## Scope

In:

- `bench/cpu.rb`: runs a fixed CPU workload (nestest in automation mode, looped from a fresh state until N million
  cycles) and reports emulated cycles per second and the ratio to real time.
- Warm-up runs before measuring; median of several runs; `ruby -v`, JIT flags and machine info in the output.
- `rake bench:cpu` running the three configurations and writing `docs/benchmarks.md` (appending a dated section).
- Variant experiments for the open decisions, each behind a flag in the harness (not in the core):
  dispatch strategy, memory container (Array vs String vs IO::Buffer), status register representation (Integer vs
  one ivar per flag, swapped inside `Cpu::Status`, plan 05), and
  `Ruby::Nes::Bits` helpers (`Bits.wrap_to_byte(value)`) vs inline operators with `# glossary:` tags (decision 3 in
  `docs/architecture.md`). If a JIT makes the helpers free, narrow the hot-path exception in `docs/architecture.md`
  (the single source of truth) and its Decisions log; `CLAUDE.md` only summarises it.

Out: optimising the PPU/APU (plan 25).

## Open decisions

- Workload size and number of runs (target: each configuration under ~1 minute).
- Whether to add `benchmark-ips` or keep a stdlib-only harness. Recommendation: stdlib only (`Process.clock_gettime`);
  fewer moving parts across JITs.

## Tasks

- [ ] Write the harness and rake task (the harness is tooling, not behaviour: no spec tree required beyond a smoke
      test that it runs a tiny workload).
- [ ] Run the three configurations; record results.
- [ ] Run the variant experiments under the best JIT and the interpreter; pick winners; update plan 01's decisions in
      `docs/architecture.md`.
- [ ] Capture `--yjit-stats` / `--zjit-stats` highlights (side exits, compiled methods) for the hot methods.

## Acceptance criteria

- [ ] `bundle exec rake bench:cpu` produces a table: configuration × emulated MHz × % of real time.
- [ ] Results are reproducible within ~5% across two invocations on the same machine (document the variance).
- [ ] Each hot-path open decision has a recorded winner with numbers.
- [ ] `docs/benchmarks.md` states which JIT the project defaults to for now, and why.

## References

- YJIT documentation — https://docs.ruby-lang.org/en/master/yjit/yjit_md.html
- ZJIT documentation — https://docs.ruby-lang.org/en/master/zjit_md.html (if the path moved, `doc/zjit.md` in https://github.com/ruby/ruby)
- Cycle reference chart — https://www.nesdev.org/wiki/Cycle_reference_chart
- `IO::Buffer` — https://docs.ruby-lang.org/en/master/IO/Buffer.html
