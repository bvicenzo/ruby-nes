# 26 — Spinel AOT experiment

**Depends on:** 10 (CPU-only experiment), 25 (full emulator experiment)

## Goal

Find out whether matz/spinel can compile ruby-nes (or its core) into a native executable, what it costs in code
changes, and how its speed compares with CRuby + JIT. Milestone M8. The outcome is knowledge: "it does not compile,
and here is why" is a valid result.

## Context

From the project README: "Spinel compiles Ruby source code into standalone native executables. It performs
whole-program type inference and generates optimized C code, achieving significant speedups over CRuby." Whole-program
type inference usually means a subset of Ruby (limited dynamic features, monomorphic types). The core was written with
that in mind (plan 01: explicit requires, no metaprogramming on hot paths, integer arithmetic), but nothing about
Spinel's actual supported subset is assumed here: step 1 establishes it.

## Scope

In:

1. Read the Spinel repository (README, docs, examples, issues) and write down the supported subset, build
   requirements, and how it handles stdlib (`zlib`, `optparse`), C extensions and FFI.
2. Stage A — CPU only: a headless entry point that runs nestest in automation mode and prints the trace. Compile it;
   compare its trace to `nestest.log`; benchmark against plan 10's numbers.
3. Stage B — full core, headless: run N frames of SMB3 with scripted input; compare frame digests with CRuby;
   benchmark against plan 25's numbers.
4. Stage C (only if B works and Spinel can call native libraries) — windowed frontend.

Out: maintaining a Spinel build in CI; Spinel-only code paths in the core without the user's approval.

## Open decisions

- If Spinel needs code changes: accept changes that keep the code idiomatic and CRuby-fast; anything else stays on an
  experiment branch. Each change is presented to the user before landing on the main branch.

## Tasks

- [ ] Step 1 findings in `docs/spinel.md`.
- [ ] Stage A: build, verify the trace, benchmark.
- [ ] Stage B: build, verify digests, benchmark.
- [ ] Stage C if applicable.

## Acceptance criteria

- [ ] `docs/spinel.md` documents: supported subset as found, every compile error met and how (or whether) it was
      resolved, code changes required, correctness check results, and a benchmark table (Spinel vs no JIT / YJIT /
      ZJIT) for each stage reached.
- [ ] The CRuby suite stays green after any change made for Spinel.
- [ ] A clear conclusion paragraph: how far Spinel got and what it would take to go further.

## References

- Spinel — https://github.com/matz/spinel
- Plan 10 and plan 25 benchmark results — `docs/benchmarks.md`
