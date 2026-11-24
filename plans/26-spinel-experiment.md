# 26 — Spinel AOT experiment

**Status:** done (2026-11-24)

**Depends on:** 10 (CPU-only experiment), 25 (full emulator experiment)

## Goal

Find out whether matz/spinel can compile ruby-nes (or its core) into a native executable, what it costs in code
changes, and how its speed compares with CRuby + JIT. Milestone M8. The outcome is knowledge: "it does not compile,
and here is why" is a valid result. If it compiles, the result is `bin/ruby-nes`, the native twin of `exe/ruby-nes`.

## Context

From the project README: "Spinel compiles Ruby source code into standalone native executables. It performs
whole-program type inference and generates optimized C code, achieving significant speedups over CRuby." Whole-program
type inference usually means a subset of Ruby (limited dynamic features, monomorphic types). The core was written with
that in mind (plan 01: explicit requires, no metaprogramming on hot paths, integer arithmetic), but nothing about
Spinel's actual supported subset is assumed here: step 1 establishes it.

What its repository says when the plan starts (2026-11-24; README, `docs/require.md`, `docs/limitations.md`, issue
#9898), to be confirmed by step 1:

- A C binary on libprism that infers types and calls `cc`. Releases are dated tags (the first is `2026.09.12`); the
  release tarball carries the vendored parsers and builds with `make` alone. macOS on Intel with clang is supported.
- `require_relative` is resolved at compile time over the whole program; issue #9898 moved it to CRuby's load model
  (per-file scopes, requires run where they stand).
- `optparse`, `zlib`, `digest`, `yaml` (a subset of psych) and `set` are Ruby sources spliced in when required. No C
  extensions and no `ffi` gem: Spinel has its own FFI (`ffi_lib`, `ffi_func`, `ffi_buffer` inside a `module`).
- No `eval`, `method_missing`, or `send`/`define_method` with a name computed at run time; no ObjectSpace.
- Integers are 64-bit words, `--int-overflow=raise|wrap|promote` (default `raise`).
- `make optcarrot` is one of its integration tests: a NES emulator in Ruby already compiles with it.

Spots of ruby-nes that may meet a refusal: the dynamic `require library` of `CommandLine::RaylibWindow` (window only),
`RubyVM.const_get` (`CommandLine::Jit`) and `::Raylib.const_get` (`Frontends::Raylib`), `Kernel.method(:sleep)`
(`Frontends::FramePacing`, `Frontends::AudioPacing`), the `it` block parameter, `Data.define`/`Struct.new`, and
`Array#pack` (digests, PNG). The raylib-bindings gem rests on the `ffi` gem, so the window seemed to need a raylib
binding of its own in Spinel's FFI. (Refuted: Spinel bundles a package implementing the `ffi` gem's API; decision 8.)

## Scope

In:

1. Step 1 — `rake spinel:fetch` downloads and builds a pinned Spinel release into `tmp/spinel/`. Small probe programs
   (outside the repository) with the core's patterns establish the supported subset; the findings, the build
   requirements and how Spinel handles stdlib and FFI go to `docs/spinel.md`.
2. Stage A — CPU only: `spinel/cpu.rb` checks nestest's trace in automation mode against the whole of `nestest.log`
   (reusing `Nestest::Runner` and `Nestest::Log`) and aborts on a divergence, then measures plan 10's workload
   (`CpuBenchmark::Workload`).
3. Stage B — full core, headless: `spinel/frames.rb`, the workload of `bench/frame_benchmark/workload.rb` (SMB3 with
   its input script and audio on, 1200 warm-up frames and 5 runs of 60), printing the frame and audio digests, which
   must be CRuby's (`f0903fbc59bf` / `10369a5b40df`).
   One `rake bench:spinel` compiles both programs and runs them on CRuby (no JIT, YJIT, ZJIT) and compiled (without
   and with the type seeds of decision 7, and with `--int-overflow=wrap`), and appends both tables to
   `docs/benchmarks.md` (decision 5).
4. Stage C (only if B works) — windowed frontend: `exe/ruby-nes` with the raylib-bindings gem, which Spinel's bundled
   `ffi` package can compile as it is (this replaced the plan's own raylib binding in Spinel's FFI: see decision 8),
   and a `rake spinel:build` that writes `bin/ruby-nes`.

Out: maintaining a Spinel build in CI; Spinel-only code paths in the core without the user's approval.

## Decisions

1. **`bin/ruby-nes` is generated and gitignored.** `rake spinel:build` writes it. A native binary is
   platform-specific and a few MB, so it stays out of the history; the gemspec already leaves `bin/` out of the gem.
2. **Stage C is isolated.** What only Spinel needs (an entry point, workarounds for Spinel's bugs) lives in `spinel/`,
   outside `lib/`; the core does not change for it. Each piece is shown to the user before it lands on the main branch.
   (A raylib binding of our own in Spinel's FFI turned out unnecessary: decision 8.)
3. **Changes to `lib/` for Spinel** land on the main branch only if they keep the code idiomatic and CRuby-fast
   (`rake bench:frames` keeps its digests and does not slow down under YJIT). Each change is presented to the user
   first; anything else stays on a `spinel-experiment` branch. In the end `lib/` did not change.
4. **Spinel is pinned to a release.** `rake spinel:fetch` downloads the latest dated release tarball into
   `tmp/spinel/` (gitignored) and builds it with `make`, never `make install`. The tag goes into `docs/spinel.md`, so
   the result can be reproduced.
5. **Entry points run in both worlds.** The scripts in `spinel/` are plain Ruby that CRuby runs too, so the same source
   gives the reference output (trace, digests) and the timing on both sides. `spinel/cpu.rb` checks the trace and
   measures plan 10's workload; `spinel/frames.rb` measures plan 25's. Neither uses `OptionParser`: the paths and sizes
   come as arguments from `rake bench:spinel`.
6. **TDD.** The `spinel/` scripts are thin compositions. New behaviour (a digest of our own, a frontend adapter, a
   refactoring of `lib/` that changes a shape) goes through the TDD cycle; a refactoring of `lib/` with no new
   behaviour is covered by the existing suite. The CRuby side of each entry point gets an example as a context of that
   entry point: the nestest trace matches the log (`test_rom:`), the frames' digests match the workload's
   (`test_rom:`, on nestest, so no local dump is needed).
7. **Type seeds outside the code.** Out of the box the mappers' hierarchy and the buses' device slots widen the integers
   flowing through them to untyped, and Spinel runs them on its boxed slow path (the CPU alone was slower than YJIT).
   The fix lives in `spinel/sig/nes.rbs`, RBS that `spinel --rbs` reads and CRuby never does, not in inline `#:`
   comments in `lib/`. `rake bench:spinel` measures without the seeds, with them, and with them and
   `--int-overflow=wrap`.
8. **Stage C stops where Spinel stops.** `exe/ruby-nes` with the raylib-bindings gem compiles (Spinel's `ffi` package
   implements the gem's API, so no binding of our own is needed), but only with refusals deferred, and the window does
   not open: Spinel bugs in its `optparse` package and in whole-program inference (one, in `Frontends::Viewport`, with
   no workaround found), plus two changes `lib/` would need (`Kernel.method(:sleep)`, the raylib library's path without
   `Gem::Specification`). The plan closes with stages A and B and Stage C documented as far as it got
   (`docs/spinel.md`); no `bin/ruby-nes` is built (decision 1 stands for when one is), and the window waits for Spinel
   to mature. Reproductions of the Spinel bugs are drafted in `docs/spinel.md`; filing them is the user's call.

## Tasks

- [x] Step 1: `rake spinel:fetch`, probes, findings in `docs/spinel.md`.
- [x] Stage A: build, verify the trace, benchmark.
- [x] Stage B: build, verify digests, benchmark.
- [x] Stage C, as far as it went: compiles with refusals deferred, the window does not open; documented in
      `docs/spinel.md` (decision 8).

## Acceptance criteria

- [x] `docs/spinel.md` documents: the Spinel tag and commit, the supported subset as found, every compile error met
      and how (or whether) it was resolved, code changes required, correctness check results (nestest trace, SMB3
      digests), and a benchmark table (Spinel, under each overflow mode measured, vs no JIT / YJIT / ZJIT) for each
      stage reached.
- [x] The CRuby suite stays green after any change made for Spinel (`SLOW=1 RUBYOPT=--yjit bundle exec rake` when
      `lib/` changes), and `rake bench:frames` keeps its digests with no loss under YJIT.
- [x] Stage C is documented as far as it got: what compiles, every obstacle met and its workaround, and what is left
      before a `bin/ruby-nes` could play SMB3 in a window (decision 8). Not reached: no `bin/ruby-nes` is built.
- [x] A clear conclusion paragraph: how far Spinel got and what it would take to go further.

## What was done

- `rake spinel:fetch` builds Spinel 2026.10.25 under `tmp/spinel` (pinned, its revision stamped right).
- `spinel/cpu.rb` and `spinel/frames.rb`, plain Ruby that CRuby runs too, reuse the CPU and the frame benchmarks
  (whose printed line moved to `CpuBenchmark::Measurement` / `FrameBenchmark::Measurement`, whose errors moved to
  `bench/cpu_benchmark/errors.rb`, and whose `Configuration.current` names another engine after itself).
- `rake bench:spinel` compiles them without and with the type seeds of `spinel/sig/nes.rbs` and with
  `--int-overflow=wrap`, and measures them next to no JIT, YJIT and ZJIT.
- Results (`docs/spinel.md`): the whole core compiles with no change to `lib/`; the nestest trace and Super Mario
  Bros. 3's frame and audio digests are CRuby's; the game runs at 95 frames per second out of the box (1.5× YJIT),
  179 with the seeds and wrapping integers (2.75× YJIT). The window does not run (decision 8).

## References

- Spinel — https://github.com/matz/spinel (README, `docs/require.md`, `docs/limitations.md`, `docs/FFI.md`, issue
  #9898 on the load model)
- Plan 10 and plan 25 benchmark results — `docs/benchmarks.md`
