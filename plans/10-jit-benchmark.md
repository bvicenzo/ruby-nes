# 10 — JIT benchmark: interpreter vs YJIT vs ZJIT

**Status:** done (2026-11-18)

**Depends on:** 09

## Goal

Measure how fast the CPU core runs on Ruby 4.0.9 without a JIT, with YJIT and with ZJIT, using a reproducible
harness, and use it to settle the hot-path decisions that `docs/architecture.md`'s Decisions log left to this plan:
memory container (2), `Bits` helpers vs inline operators (3), status register representation (6), opcode dispatch
(9, 18) and the interrupt poll's method call per step (13). Milestone M2.

## Context

The real CPU runs ~1.789773 MHz; a frame is ~29 780 CPU cycles. The CPU is only part of the work (the PPU does three
dots per CPU cycle and usually dominates), so this benchmark is an upper bound on what a full frame will cost, not a
verdict.

Ruby 4.0.9 exposes `--yjit` and `--zjit` (both disabled by default), with `--yjit-stats` / `--zjit-stats` for
compilation statistics. ZJIT is the newer method-based JIT; whether it beats YJIT on this workload is what this plan
measures, not what it assumes.

A probe made while refining the plan (i5-8257U, Ruby 4.0.9 x86_64-darwin24, 2026-11-18) gave about 3.6 emulated MHz
without a JIT, 11.5 with YJIT (no side exits) and 2.2 with ZJIT: `--zjit-stats` counts 248 million `Integer#===`
calls, so ZJIT compiles the dispatch's 256-`when` `case` as a linear search instead of `opt_case_dispatch`'s jump
table. The dispatch experiment is therefore central.

One nestest pass in automation mode is 8991 instructions (the lines of nestest.log), about 26 550 cycles; after its
last `RTS` the CPU runs into garbage, so a pass is a fixed number of steps from a fresh console.

## Scope

In:

- `bench/cpu.rb` and the `CpuBenchmark` tooling in `bench/cpu_benchmark.rb` + `bench/cpu_benchmark/`, specs in
  `spec/cpu_benchmark/`: runs nestest passes (built by plan 08's `Nestest::Runner.automation_mode` in
  `spec/support/nestest/`) from a fresh console until N cycles, checks `$0002`/`$0003` after each pass, and reports
  emulated MHz and the percentage of real time.
- Warm-up runs before measuring; median of several runs; `RUBY_DESCRIPTION`, JIT configuration and machine info in
  the output.
- `rake bench:cpu` (the three configurations, baseline code) and `rake bench:variants` (every variant under the three
  configurations), each appending a dated section to `docs/benchmarks.md`.
- Variant experiments, each a file under `bench/cpu_benchmark/variants/` loaded by a flag of the harness (never by
  the core): dispatch as a table of lambdas and as a two-level `case` (both generated from `dispatch.rb`'s source),
  memory as `String` and as `IO::Buffer` (the `CpuBus` RAM and `Nrom`'s PRG ROM/RAM), status as one ivar per flag,
  `Bits` helpers on the per-instruction path (fetch, addressing mode resolvers, `CpuBus#read`/`#write`), and the
  interrupt poll inlined in `Cpu#step`.
- Applying a clear winner to the core (see decision 6) and updating `docs/architecture.md` (the single source of
  truth: decisions 2, 3, 6, 9, 13, 18 and the layout); `CLAUDE.md` only summarises it.

Out: optimising the PPU/APU (plan 25).

## Decisions

Settled with the user on 2026-11-18.

1. **Workload:** 10 million cycles per run, 2 warm-up runs and 5 measured runs, median. Each configuration stays
   under about a minute (the probe: ~20 s without a JIT, ~35 s with ZJIT, ~7 s with YJIT).
2. **Stdlib only** (`Process.clock_gettime(Process::CLOCK_MONOTONIC)`), no `benchmark-ips`: fewer moving parts across
   JITs.
3. **Variants reopen core classes inside the benchmark process**, one process per configuration × variant, so the
   core and the spec suite never see them. Refinements were considered and discarded: their activation is lexical,
   so a `using` in `bench/` never reaches the calls made inside `lib/` (`Cpu#step` calling `execute`, `fetch_byte`
   calling `@bus.read`), and refined methods take their own lookup path in the JITs, which would skew the numbers.
   Each pass checks nestest's result bytes, so a broken variant aborts instead of being measured.
4. **Every variant runs under the three configurations** (no JIT, YJIT, ZJIT): ZJIT's behaviour is part of the study.
5. **Dispatch variants:** a table of 256 lambdas and a two-level `case` (high nibble, then 16 `when`s), both
   generated from `dispatch.rb`'s source with Prism, so the opcode map is never duplicated by hand.
6. **A clear winner is applied to the core in this plan:** faster beyond the noise (> 5%) under the default JIT and
   not markedly slower under the others. The spec suite and nestest guard the change. Otherwise the numbers are only
   recorded.

Settled during implementation:

7. **A variant's trace is compared with the whole of nestest.log before it is measured** (`CommandLine`, untimed),
   on top of the result bytes each pass checks. Reason: a `bits_helpers` variant that read the program counter before
   fetching the branch offset missed every branch target by one byte and still left `$0002`/`$0003` at zero; it was
   "measured" 64% faster under YJIT. Its numbers were discarded and every variant re-measured with the check.
8. **`baseline` is a variant** (a file that reopens nothing), so the command line always loads one file, and the
   variants table carries a baseline from its own session. Sessions half an hour apart drifted up to 14% without a
   JIT, so a variant is compared only with its session's baseline.
9. **The two-level dispatch is applied** (decision 6; user's choice over the table of lambdas): +21% under YJIT,
   +261% under ZJIT, −6% without a JIT. Each row's column 2 is its `case`'s `else` and row F the outer `else`, so no
   implicit `else` is left for branch coverage. `DispatchSource` reads the row `case`s, and the
   `dispatch_two_level_case` variant was removed once it equalled the core.
10. **`Bits` helpers stay off the hot paths** (user's choice): free under YJIT on the measured path but −14% without
    a JIT, and that path is a lower bound; plan 25 measures the full conversion.
11. **YJIT is the default JIT** (architecture decision 19). Memory stays an `Array` and the interrupt poll a method
    call: no clear winner under YJIT.

Review follow-ups (independent code review, accepted by the user):

12. **Only the instructions are timed:** `Workload` reads the clock around each pass's steps and returns the Sample,
    so building the console is not measured. The first variants table counted it, which inflated the memory variants'
    losses (they converted 26 KiB per pass); every table was measured again. `Workload` takes the steps per pass from
    nestest.log's line count instead of a constant.
13. Plans 05 and 06 had left three hot-path micro-changes to this plan (the program counter advance in
    `immediate_address`, a one-expression `update_zero_and_negative`, a `BASE_CYCLES` array); they were not measured
    here and became plan 25 leads. The benchmark needs a Ruby built with both YJIT and ZJIT; `Configuration` reads
    each constant only when it is defined, so the specs also run on a Ruby built without one (second review).
14. Also applied: `bench/` excluded from the gem, the bench loaded only by its own specs, `Options::WORKLOAD_DEFAULTS`
    naming the workload in the report titles, glossary order and acronym lists, small constant and naming fixes, the
    RTS cycle count cited. Not applied: generating the variant smoke contexts from `Variants::NAMES` (the project
    forbids dynamic example generation).
15. **One ivar per status flag is applied** (user's choice, re-measured after follow-up 12): +6.5% under YJIT in the
    variants session and +4.8% to +5.1% in three more YJIT runs, +7% without a JIT, +5% under ZJIT. The interrupt poll's
    +6.2% did not hold in the same repeats (0% to +3%). The `status_flag_ivars` variant was removed once it equalled
    the core.

Second review (independent, accepted by the user):

16. No correctness bug: the new `Status` matches the old one on every byte, setter and `update_zero_and_negative` pair,
    and the two-level dispatch maps all 256 opcodes as before. Applied: `Configuration.current` takes booleans and
    reads `RubyVM::YJIT`/`RubyVM::ZJIT` only when defined (CI's Ruby may lack ZJIT), `Configuration::FLAGS` as the one
    list of configurations, variants run right after their configuration's baseline, the status decision recorded
    as taken at the edge of the criterion (with the repeated runs), two `DispatchSource` leaves (a row's non-JAM
    `else`, row F), and documentation fixes. Not applied: a shared nestest-loading helper for the rake task and the
    command line (it would reshape plan 08's tooling for little), and shared examples for the smoke contexts (shared
    blocks only mirror shared production code).

## What was done

- `bench/cpu.rb` and `CpuBenchmark` (`bench/cpu_benchmark/`): `Workload` (nestest passes from a fresh console, the
  clock around the instructions only, result bytes checked), `Sample`, `Summary` (median, % of real time, spread),
  `Session`, `Options`, `Configuration`, `Variants`, `DispatchSource` (the opcode map read with Prism), `CommandLine`
  (the trace compared with the whole of nestest.log before measuring) and `Report`; `rake bench:cpu` and
  `rake bench:variants` append dated sections to `docs/benchmarks.md`. Variants in `bench/cpu_benchmark/variants/`:
  baseline, lambda table, `String` and `IO::Buffer` memory, `Bits` helpers, inline interrupt poll (the two-level
  dispatch and the status ivars became the core and lost their variant files).
- Core: `Cpu::Dispatch#execute` became a two-level `case` laid out as the opcode matrix, and `Cpu::Status` one
  boolean ivar per flag. nestest under YJIT went from about 11.8 to 16.4 emulated MHz (915% of real time), under
  ZJIT from 2.2 to 9.0, and without a JIT from 3.5 to 3.7.
- `docs/benchmarks.md` (method, findings, JIT statistics, every table); `docs/architecture.md`: layout rows for
  `bench/`, decisions 2, 3, 5, 6, 9, 13 and 18 revisited, decision 19 (YJIT by default); `docs/GLOSSARY.md`: JIT,
  JSON, YJIT, ZJIT and the byte form of `high-nibble`. Plans 18 and 25 aligned. 1145 examples, 100% line and branch
  coverage; two independent code reviews (follow-ups above).

## Tasks

- [x] Harness, test first: `CpuBenchmark::Workload`, `::Summary`, `::Session`, `::Variants`, `::CommandLine`
      (`bench/cpu.rb`; a smoke context runs each variant in a subprocess on a tiny workload), `::Report`.
- [x] Variant files (validated by the command line's smoke context).
- [x] `rakelib/bench.rake`: `bench:cpu` and `bench:variants`.
- [x] Run the three configurations twice; record results and their variance.
- [x] Run the variants; pick winners; apply clear winners to the core; update `docs/architecture.md`.
- [x] Capture `--yjit-stats` / `--zjit-stats` highlights (side exits, compiled methods, fallbacks), as totals of
      the run; attributing them to methods belongs to plan 25's profiling.
- [x] `docs/GLOSSARY.md`: JIT, YJIT, ZJIT (and any other new acronym); `docs/architecture.md` layout row for `bench/`.

## Acceptance criteria

- [x] `bundle exec rake bench:cpu` produces a table: configuration × emulated MHz × % of real time.
- [x] Results are reproducible within ~5% across two invocations on the same machine (document the variance).
- [x] Each hot-path decision (2, 3, 6, 9/18, 13) has a recorded winner with numbers; clear winners are applied.
- [x] `docs/benchmarks.md` states which JIT the project defaults to for now, and why, with the stats highlights.
- [x] 100% branch coverage of the new units; rubocop clean; `bundle exec rake` green.

## References

- YJIT documentation — https://docs.ruby-lang.org/en/master/yjit/yjit_md.html
- ZJIT documentation — https://docs.ruby-lang.org/en/master/zjit_md.html (if the path moved, `doc/zjit.md` in https://github.com/ruby/ruby)
- Cycle reference chart (NTSC CPU clock 1.789773 MHz) — https://www.nesdev.org/wiki/Cycle_reference_chart
- Instruction reference (RTS takes 6 cycles, in the nestest pass length) — https://www.nesdev.org/wiki/Instruction_reference#RTS
- `IO::Buffer` — https://docs.ruby-lang.org/en/master/IO/Buffer.html
- Refinements (why they do not fit) — https://docs.ruby-lang.org/en/master/syntax/refinements_rdoc.html
- Prism — https://docs.ruby-lang.org/en/master/Prism.html
