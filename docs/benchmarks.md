# Benchmarks

Speed of the emulator under the interpreter, YJIT and ZJIT. `rake bench:cpu` and `rake bench:variants` (plan 10)
append dated sections at the end of this file; the conclusions drawn from them are written by hand in
[Findings](#findings).

How to read the tables:

- **Emulated MHz** — the median of the measured runs, in millions of emulated CPU cycles per second.
- **% of real time** — that speed relative to the NTSC CPU's 1.789773 MHz
  ([Cycle reference chart](https://www.nesdev.org/wiki/Cycle_reference_chart)); 100% keeps pace with a real console.
  The CPU is only part of a frame (the PPU runs three dots per CPU cycle), so this is an upper bound.
- **Spread** — the largest distance of one run from the median, as a percentage of the median.
- **Change from baseline** — a variant's speed relative to the unmodified core, measured under the same configuration
  in the same session. The variants sessions of 2026-11-18 ran the three baselines first and the variants after them,
  so the last variants were compared with a baseline several minutes older; `rake bench:variants` now runs each
  configuration's variants right after its baseline.

The workload is nestest in automation mode: one pass is its 8991 instructions (26 553 cycles) from a freshly
powered-up console, repeated until 10 million cycles. Before measuring, the trace is compared with the whole of
nestest.log, and each pass checks nestest's result bytes, so a variant that breaks the CPU aborts instead of being
measured (the result bytes alone are not enough: a variant that missed every branch target by one byte kept them at
zero). Each configuration and variant runs in a process of its own.

## Findings

Plan 10, 2026-11-18, on the machine of the tables below (Intel Core i5-8257U, macOS, Ruby 4.0.9). The benchmark needs
a Ruby built with both YJIT and ZJIT. Unless a line says otherwise, the numbers come from the sections measured with
the clock around the instructions only (after the note in Results).

**Default JIT: YJIT.** It is the fastest configuration with every variant measured. The core as plan 10 leaves it
(two-level dispatch and one ivar per status flag: the last baseline section of 2026-11-18) runs nestest at 16.4 emulated MHz under YJIT (915% of real time), 9.0 under ZJIT (503%) and 3.7 without a JIT (208%).
Plan 18's CLI enables YJIT by default; plan 25 re-evaluates with whole frames.

**Opcode dispatch (decisions 9 and 18): two-level `case`, applied.** One `case` of 256 `when`s compiles to
`opt_case_dispatch`, but ZJIT does not use its jump table and tests the `when`s one by one:
`ruby --zjit --zjit-stats bench/cpu.rb --cycles 2000000 --warm-up-runs 1 --runs 1` counted 187 million
`Integer#===` calls for 4 million emulated cycles, about 138 per instruction, and ZJIT ran slower than the
interpreter (2.2 MHz). With a `case` on the high nibble whose `when`s each hold a `case` of 16 opcodes, the same
command without the warm-up run counts 3.7 million calls for 2 million cycles, about 5 per instruction. Measured in
the first verified variants session (console building still timed, the same for every variant): the two-level `case`
+21% under YJIT, +261% under ZJIT, −6% without a JIT; a table of 256 lambdas +6%, +367% and −6%. The two-level `case`
won under the default JIT and keeps the no-`Proc#call` rule, so `Cpu::Dispatch#execute` has that shape. Against it,
the lambda table now measures −16% under YJIT, +29% under ZJIT and +3% without a JIT.

**Status register (decision 6): one boolean ivar per flag, applied at the edge of the criterion.** The variants
session measured +6.5% under YJIT, +7.1% without a JIT and +5.1% under ZJIT. Three more YJIT runs, each variant run
right after the baseline, gave +4.8% to +5.1%, at the criterion's threshold (plan 10, decision 6), so applying it was the
user's choice:

| Round | baseline | `status_flag_ivars` | `interrupt_poll_inline` |
|---|---|---|---|
| 1 | 15.72 | 16.51 (+5.0%) | 16.18 (+2.9%) |
| 2 | 15.74 | 16.54 (+5.1%) | 16.10 (+2.3%) |
| 3 | 15.75 | 16.50 (+4.8%) | 15.64 (−0.7%) |

(YJIT, emulated MHz, `ruby --yjit bench/cpu.rb --variant NAME` with the default workload; spreads under 4%.) The
baseline measured after the change, in a later session, read 16.38 MHz under YJIT against 16.06-16.09 before it,
about +2%: sessions drift by that much, so the gain is real in every same-session comparison but small.

**Memory container (decision 2): `Array` stays.** A binary `String` (`getbyte`/`setbyte`) measured −3.6% under YJIT,
−7.0% without a JIT and +1.3% under ZJIT; `IO::Buffer` (`get_value(:U8, …)`, still experimental on 4.0.9) −24%, −13%
and −14%. The first variants session, which timed the console building, had shown −27% and −36% under YJIT: the
memory variants converted 26 KiB per pass while building it.

**`Bits` helpers vs inline operators (decision 3): inline stays, for now.** Helpers on the per-instruction path (the
fetch, the addressing mode resolvers, `CpuBus#read`/`#write`) measured +3.1% under YJIT and −4.7% under ZJIT, within
the noise, and −14% without a JIT. That path is a lower bound of a full conversion; plan 25 measures the whole of it
before the hot-path exception is narrowed.

**Interrupt poll (decision 13): `InterruptLines#acknowledge` stays.** Inlining it in `Cpu#step` measured +6.2% under
YJIT in the variants session, where it ran last and furthest from its baseline, but the three rounds above gave
between −1% and +3%: the method call per step costs little.

**JIT statistics** of the core as plan 10 leaves it, 2 million cycles in one run
(`ruby --yjit --yjit-stats bench/cpu.rb --cycles 2000000 --warm-up-runs 0 --runs 1`, and the same with `--zjit`):

| | YJIT | ZJIT |
|---|---|---|
| Compiled methods (iseqs) | 212 | 204 (none failed) |
| Side exits | 2 | 196 |
| Other | 4 480 compiled blocks, 92 invalidations | 2.7 million dynamic sends (7% of 38.5 million), 971 thousand getivar and 237 thousand setivar fallbacks (not monomorphic), 3.7 million `Integer#===` |

**Reproducibility.** Two `rake bench:cpu` invocations in a row agreed within 1.7% (no JIT), 0.1% (YJIT) and 1.3%
(ZJIT). Sessions further apart drift more (the interpreter's baseline read 3.47 and 3.96 MHz in sessions half an hour
apart, likely thermal and turbo state), which is why each variant is compared with a baseline from its own session.
The spread within a session stayed under 4% except an interpreter baseline at 5.1% and a ZJIT baseline at 9.8%.

## Results

The first four sections below timed each pass's console building along with its instructions: measured apart in the
plan 10 review, building a console took about 66 µs of a 1.8 ms pass for the baseline under YJIT (4%), and about
850 µs for the memory variants, which converted 26 KiB per pass (up to 31%). The plan 10
review moved the clock around the instructions only; the sections after the note below are measured that way, and
the Findings use them. The earlier ones are kept as the record of the one-`case` dispatch.

### 2026-11-18 — CPU baseline (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 3.48 | 195% | 1.0% | — |
| yjit | baseline | 11.94 | 667% | 0.5% | — |
| zjit | baseline | 2.21 | 124% | 2.0% | — |

One `case` of 256 `when`s (first invocation).

### 2026-11-18 — CPU baseline (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 3.47 | 194% | 2.1% | — |
| yjit | baseline | 11.71 | 654% | 3.9% | — |
| zjit | baseline | 2.22 | 124% | 9.8% | — |

One `case` of 256 `when`s (second invocation, for the variance).

### 2026-11-18 — CPU variants (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 3.96 | 221% | 5.1% | — |
| yjit | baseline | 12.86 | 718% | 2.9% | — |
| zjit | baseline | 2.50 | 140% | 0.7% | — |
| interpreter | dispatch_lambda_table | 3.74 | 209% | 0.8% | -5.7% |
| yjit | dispatch_lambda_table | 13.67 | 764% | 2.0% | +6.4% |
| zjit | dispatch_lambda_table | 11.68 | 653% | 2.7% | +367.4% |
| interpreter | dispatch_two_level_case | 3.72 | 208% | 0.6% | -6.2% |
| yjit | dispatch_two_level_case | 15.61 | 872% | 2.2% | +21.4% |
| zjit | dispatch_two_level_case | 9.02 | 504% | 1.5% | +261.0% |
| interpreter | memory_string | 3.44 | 192% | 0.8% | -13.3% |
| yjit | memory_string | 9.43 | 527% | 2.9% | -26.7% |
| zjit | memory_string | 2.38 | 133% | 0.5% | -4.7% |
| interpreter | memory_io_buffer | 3.28 | 183% | 0.8% | -17.2% |
| yjit | memory_io_buffer | 8.21 | 459% | 3.3% | -36.1% |
| zjit | memory_io_buffer | 2.30 | 128% | 0.6% | -8.2% |
| interpreter | status_flag_ivars | 4.29 | 240% | 0.8% | +8.4% |
| yjit | status_flag_ivars | 12.87 | 719% | 1.0% | +0.1% |
| zjit | status_flag_ivars | 2.57 | 144% | 3.8% | +2.8% |
| interpreter | bits_helpers | 3.42 | 191% | 0.6% | -13.7% |
| yjit | bits_helpers | 12.89 | 720% | 1.1% | +0.3% |
| zjit | bits_helpers | 2.49 | 139% | 2.0% | -0.4% |
| interpreter | interrupt_poll_inline | 4.15 | 232% | 1.4% | +4.7% |
| yjit | interrupt_poll_inline | 13.06 | 730% | 1.6% | +1.6% |
| zjit | interrupt_poll_inline | 2.56 | 143% | 0.6% | +2.3% |

Every variant's trace was compared with nestest.log before it was measured. `dispatch_two_level_case` became the
core's dispatch afterwards, so its variant file was removed.

### 2026-11-18 — CPU baseline (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 3.35 | 187% | 2.4% | — |
| yjit | baseline | 14.68 | 820% | 3.0% | — |
| zjit | baseline | 8.48 | 474% | 2.7% | — |

The core after the two-level dispatch was applied.

---

Measured with the clock around each pass's instructions only (plan 10 review).

### 2026-11-18 — CPU baseline (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 3.57 | 200% | 3.6% | — |
| yjit | baseline | 16.08 | 898% | 0.9% | — |
| zjit | baseline | 8.98 | 502% | 1.2% | — |

### 2026-11-18 — CPU baseline (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 3.63 | 203% | 1.3% | — |
| yjit | baseline | 16.09 | 899% | 0.8% | — |
| zjit | baseline | 8.86 | 495% | 1.8% | — |

### 2026-11-18 — CPU variants (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 3.63 | 203% | 0.5% | — |
| yjit | baseline | 16.06 | 897% | 1.1% | — |
| zjit | baseline | 9.00 | 503% | 0.7% | — |
| interpreter | dispatch_lambda_table | 3.73 | 208% | 0.4% | +2.6% |
| yjit | dispatch_lambda_table | 13.54 | 757% | 2.7% | -15.7% |
| zjit | dispatch_lambda_table | 11.64 | 650% | 1.0% | +29.2% |
| interpreter | memory_string | 3.37 | 189% | 2.1% | -7.0% |
| yjit | memory_string | 15.48 | 865% | 0.5% | -3.6% |
| zjit | memory_string | 9.12 | 510% | 1.4% | +1.3% |
| interpreter | memory_io_buffer | 3.15 | 176% | 1.6% | -13.3% |
| yjit | memory_io_buffer | 12.21 | 682% | 0.7% | -23.9% |
| zjit | memory_io_buffer | 7.74 | 432% | 0.3% | -14.1% |
| interpreter | status_flag_ivars | 3.89 | 217% | 2.0% | +7.1% |
| yjit | status_flag_ivars | 17.11 | 956% | 1.2% | +6.5% |
| zjit | status_flag_ivars | 9.46 | 529% | 0.6% | +5.1% |
| interpreter | bits_helpers | 3.12 | 174% | 3.8% | -14.1% |
| yjit | bits_helpers | 16.56 | 925% | 3.1% | +3.1% |
| zjit | bits_helpers | 8.58 | 479% | 1.1% | -4.7% |
| interpreter | interrupt_poll_inline | 3.75 | 209% | 0.6% | +3.2% |
| yjit | interrupt_poll_inline | 17.06 | 953% | 1.3% | +6.2% |
| zjit | interrupt_poll_inline | 9.32 | 521% | 1.4% | +3.5% |

Measured on the two-level dispatch with the Integer status register; `status_flag_ivars` became the core's status
afterwards, so its variant file was removed.

### 2026-11-18 — CPU baseline (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 3.72 | 208% | 0.5% | — |
| yjit | baseline | 16.38 | 915% | 0.5% | — |
| zjit | baseline | 9.00 | 503% | 0.4% | — |

### 2026-11-19 — Plan 12: indexed dummy reads (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

Three `rake bench:cpu` runs in one session, merged by hand: the base commit of plan 12 (8977021), plan 12's CPU without
the dummy reads (base cycles charged before `execute`, the NMI polling point), and with them (plan 12, decision 4).
The change column compares each row with the base commit under the same configuration.

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | base commit | 3.39 | 190% | 0.8% | — |
| yjit | base commit | 14.86 | 830% | 1.2% | — |
| zjit | base commit | 7.59 | 424% | 7.0% | — |
| interpreter | without dummy reads | 3.36 | 188% | 1.4% | -0.9% |
| yjit | without dummy reads | 15.22 | 850% | 0.1% | +2.4% |
| zjit | without dummy reads | 8.52 | 476% | 1.8% | +12.3% |
| interpreter | with dummy reads | 3.37 | 188% | 0.7% | -0.6% |
| yjit | with dummy reads | 14.90 | 833% | 2.3% | +0.3% |
| zjit | with dummy reads | 8.54 | 477% | 1.8% | +12.5% |

The polling point and the earlier charge of the base cycles cost nothing measurable; the dummy reads cost about 2%
under YJIT (15.22 → 14.90) and nothing measurable under the interpreter or ZJIT. The base commit's ZJIT run has a 7%
spread, so its +12% is noise rather than a gain. The whole machine ran about 9% slower than on 2026-11-18.
