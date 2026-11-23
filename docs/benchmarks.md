# Benchmarks

Speed of the emulator under the interpreter, YJIT and ZJIT. `rake bench:cpu` and `rake bench:variants` (plan 10) and
`rake bench:frames` (plan 25) append dated sections at the end of this file; the conclusions drawn from them are written
by hand in [Findings](#findings). `rake bench:profile` prints vernier's top methods for the frame workload.

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

### Plan 31: the sprites and the horizontal blank (2026-11-23)

The same frame workload, with the same digests in every configuration and run: f0903fbc59bf (frame), 10369a5b40df
(audio).

| Configuration | Plan 30's final | Plan 31's final | Change |
|---|---|---|---|
| interpreter | 14.5 fps (68.8 ms) | 17.2 fps (58.3 ms) | -15% per frame |
| yjit | 46.6 fps (21.4 ms) | 61.5 fps (16.3 ms) | -24% per frame |
| zjit | 39.5 fps (25.3 ms) | 44.5 fps (22.5 ms) | -11% per frame |

**YJIT runs Super Mario Bros. 3 at 102% of real time.** Whether the window's audio is free of crackles at that margin
is checked by playing it (plan 31, acceptance criteria).

**Measured.** Prototypes over 8061014, A/B interleaved against a worktree of it: whole frames (median of 5 runs of 60
after the 1200 warm-up frames) and `Renderer#run_dots` over a visible line's dots 1-340, or only the dots a step
touches (a throwaway script). The machine drifted by a few percent between rounds, so each step took 3-8 rounds.

| Step (cumulative) | Frame | Visible line 1-340 | Kept |
|---|---|---|---|
| Base (8061014) | ~21.5 ms | ~64 µs | — |
| Sprite-free whole tiles (`SpriteLine#occupied_tiles`) | ~-2% | ~-3% | yes |
| + whole sprite slots, the first dot through `run_dot` | ~17.5 ms | ~49 µs | yes |
| + a slot's first dot skipped when it only resets OAMADDR (all but 257) | ~-3% | ~-3% | yes |
| + the next line's two tiles whole (dots 321-340: 3.1 → 1.6 µs) | ~-2% | — | yes |
| Lines with no step returning at once (3 µs → 0.05 µs a line, about 20 lines a frame) | ~-0.3% | — | no |
| Built test first, the plan's final tree | 16.3-16.5 ms (-24%) | ~43 µs (-33%) | — |

**Findings.**

- `SpriteRenderer#run_steps` was about 11% of a frame on its own: it ran on every dot 257-320, 64 times a line, only
  because OAMADDR is reset on each. A whole slot calls the sprite renderer once and resets OAMADDR once; it is now
  about 1%.
- A sprite-free tile saves the sprite line's read and comparison per pixel: small (about 2%), since a call per pixel
  was already gone (plan 30).
- The lines with no step cost about 3 µs each to walk dot by dot, about 0.06 ms a frame: not worth a branch.

**The rest, under YJIT**, from vernier's top methods (200 frames, self time):

| Component | Share |
|---|---|
| Background fetches (`Mappers::Base#ppu_read`, `Renderer#fetch_tile`, the fetcher, `PpuBus`, `Mmc3#ppu_read`, nametables) | ~27% |
| Pixel (`Renderer#run_tile`, `PixelComposer#draw_background_tile` and `#draw_tile`, the window, the per-dot pixels) | ~18% |
| The loops (`Renderer#run_dots`, `#run_dot`, `#run_whole_sequence`, `Console#run_frame`) | ~16% |
| CPU and CPU bus | ~9% |
| Sprites (the evaluation, `run_steps`, `run_slot`, `SpriteLine#place`) | ~4% |
| APU and audio | ~3% |

### Plan 30: the background pipeline per tile (2026-11-23)

The same frame workload, with the same digests in every configuration and run: f0903fbc59bf (frame), 10369a5b40df
(audio).

| Configuration | Plan 29's final | Plan 30's final | Change |
|---|---|---|---|
| interpreter | 10.2 fps (97.7 ms) | 14.5 fps (68.8 ms) | -30% per frame |
| yjit | 34.1 fps (29.3 ms) | 46.6 fps (21.4 ms) | -27% per frame |
| zjit | 30.3 fps (33.0 ms) | 39.5 fps (25.3 ms) | -23% per frame |

**Measured on a visible line.** Whole frames A/B on this machine drifted by up to 8% between rounds, so each step was
also timed as `Renderer#run_dots` over dots 1-256 of a visible line, after the 1200 warm-up frames (a throwaway script,
A/B interleaved against a worktree of 65e1705, ±2%).

| Step (cumulative) | µs per visible line | Kept |
|---|---|---|
| Base (65e1705) | ~68-77 | — |
| Prototype: colours precomputed, the renderer storing into the drawn frame, the window, a `compose` call per pixel | ~71 | partly |
| Prototype: + the 8 pixels composed inline in one method | ~53 | yes |
| Prototype: + the window computed inline in `run_tile` | ~54-57 | no |
| Prototype: + the fetcher reading the nametables and the board without `PpuBus#read` | ~53 | no |
| Prototype: + mirroring kept by the nametables (upper bound of pushing it) | ~50.5 | yes, pushed |
| Prototype: + the attribute address and quadrant by tables | ~43.5 | yes |
| Prototype: + one spread table per bit plane | ~40.5 | yes |
| Prototype: `Mappers::Base#ppu_read` without its local | ~40.5 | no |
| Prototype: mirroring cached by an identity check instead of pushed | ~41-43 | no |
| Built: colours, the composer, the window (frame index computed inside `draw_tile`) | ~57 | no: see below |
| Built: the same, the frame index handed in | ~45 | yes |
| Built: + the attribute tables and the mirroring pushed (the plan's final tree) | ~35 (-50%) | — |

Whole frames, A/B interleaved, three rounds: 28.4 ms became 20.7 ms (-27%).

**YJIT findings.**

- A shift by a varying amount (`>> (15 - fine_x)`, `attribute >> quadrant`) is a call to `Integer#>>`: YJIT inlines a
  shift only for an amount it has seen. A multiplication by a power of two from a table, then a constant shift, is
  inline (architecture, Hot paths).
- The calls per pixel cost more than their arithmetic: composing a tile's 8 pixels inline in one method took a visible
  line from ~71 to ~53 µs.
- An unrolled method that computed its own frame index, `(y × WIDTH) + x`, into a local ran the line at 57 µs; with
  the index handed in by the caller, 44-45 µs. The literal 256 in its place was as fast. Named mask constants against
  literals measured no difference (44.6 against 44.1 µs). The cause inside YJIT was not investigated.
- Microbenchmarks of these effects were unreliable: a measuring loop entered once is never compiled, and constant cache
  fills invalidate compiled code, moving a probe by 4×. Only the line benchmark on the real renderer was trusted.

**The gap: 20.7 ms per frame under YJIT against 16.6 ms**, about 4.1 ms. Per component, from vernier's top methods
(200 frames, self time):

| Component | Share |
|---|---|
| Pixel (`Renderer#run_tile`, `PixelComposer#draw_tile`, the window, the per-dot pixels) | ~23% |
| The loops (`Renderer#run_dots` and `#run_dot`, `Console#run_frame`, `Ppu#run_range`) | ~22% |
| Background fetches (`Mappers::Base#ppu_read`, `Mmc3#ppu_read`, the fetcher, `PpuBus`, nametables) | ~16% |
| Sprite steps (`SpriteRenderer#run_steps`, the evaluation, `SpriteLine#place`) | ~14% |
| CPU and CPU bus | ~8% |
| APU and audio | ~2% |

Plan 31 (the sprites and dots 257-340) is next.

### Plan 29: the APU's sync deadline and runs (2026-11-23)

The same frame workload, with the same digests in every configuration and run: f0903fbc59bf (frame), 10369a5b40df
(audio).

| Configuration | Plan 28's final | Plan 29's final | Change |
|---|---|---|---|
| interpreter | 7.0 fps (142.3 ms) | 10.2 fps (97.7 ms) | -31% per frame |
| yjit | 27.9 fps (35.8 ms) | 34.1 fps (29.3 ms) | -18% per frame |
| zjit | 19.4 fps (51.6 ms) | 30.3 fps (33.0 ms) | -36% per frame |

**Before starting** (throwaway instrumentation, 200 frames after the warm-up, YJIT): the APU and audio were about 20%
of the frame, and about half of it was the mix computed every cycle (`Pulse#output`, `Apu#output`, `Mixer.mix`,
`Sweep#muting?`, ...). The mix changed about 247 times a frame. Runs ending at every sequencer clock would have been
2-3 cycles long: the noise played at its fastest period (a clock every 4 CPU cycles) and ended about 3 370 runs a
frame, the DMC about 550, yet the noise could sound on 4.3% of the cycles and the DMC had a sample on 31%.

**Steps**, interleaved under YJIT against a worktree of 3c41340 (plan 28's tree, about 35-36 ms in these sessions),
every variant with identical digests:

| Variant | ms per frame | Kept |
|---|---|---|
| Sync deadline, the catch-up loop holding the cycle's body | ~37.7 (+3%) | no: see below |
| Sync deadline, the cycle's body in `Apu#run_cycle` | ~36.4 (neutral) | yes, as the base of the runs |
| + runs that end at every clock (prototype) | ~31.5 | yes |
| + muted channels do not end runs (prototype) | ~28.4 | yes |
| The plan's final tree | ~28.6 (-19%) | — |

**A YJIT finding.** The deadline alone took catch-ups from about 9 900 a frame to about 31, yet the frame got slower.
A microbenchmark of `Apu#catch_up` over the same 29 780 cycles, without audio, took 2.2 ms in catch-ups of 3 cycles and
4.2 ms in catch-ups of 3 000; the interpreter took about 16-17 ms either way. With the cycle's body moved into a method
the loop calls, both took about 2.3-2.5 ms. The emulator's catch-up loops call a method per step since (architecture
decision 82). The cause inside YJIT was not investigated.

**Not kept:** an integer `Apu::NEVER` was tried first as the cause of the slowdown above (an Integer compared with
`Float::INFINITY` on every step); it was not, but the runs need it anyway (decision 81). An integer accumulator in the
resampler was not tried: it changes the float sum's rounding, so it belongs to the fast mode (decision 77).

**The gap: 29.3 ms per frame under YJIT against 16.6 ms**, about 12.7 ms. Per component, from vernier's top methods
(200 frames, self time):

| Component | Share |
|---|---|
| Pixel composition (`Renderer#run_tile` and `#draw`, `Picture#draw`, the shifts, palette RAM) | ~36% |
| Background fetches (fetcher, `PpuBus`, nametables, mapper, MMC3) | ~22% |
| The loops (`Renderer#run_dots` and `#run_dot`, `Console#run_frame`, `Ppu#catch_up`) | ~15% |
| Sprite steps (`SpriteRenderer#run_steps`, evaluation) | ~10% |
| CPU and CPU bus | ~7% |
| APU and audio (the resampler's per-cycle additions, the runs) | ~2% |

The APU is out of the way; plans 30 and 31 (the background pipeline, the sprites and dots 257-340) hold the rest.

### Plan 28: ranges of dots (2026-11-22)

The same frame workload as plan 25, with the same digests in every configuration and run: f0903fbc59bf (frame),
10369a5b40df (audio).

| Configuration | Plan 25's final (370614b) | Plan 28's final | Change |
|---|---|---|---|
| interpreter | 5.2 fps (192.1 ms) | 7.0 fps (142.3 ms) | -26% per frame |
| yjit | 23.4 fps (42.7 ms) | 27.9 fps (35.8 ms) | -16% per frame |
| zjit | 15.4 fps (65.1 ms) | 19.4 fps (51.6 ms) | -21% per frame |

Measured against the previous final in another session. Interleaved in one session against a worktree of 370614b,
YJIT reads 44.5 against 35.9 ms (-19%).

**Why ranges alone did not pay.** `Console#step` caught the PPU up after every instruction, so each `catch_up` covered
6-21 dots. A prototype running those as ranges gained nothing, and a whole tile was rarely inside one.

**What was kept.** Throwaway prototypes, A/B interleaved, each kept step with identical digests:

1. The sync deadline (architecture decision 74): `run_frame` catches the PPU up only from its sync cycle on, three
   times a frame with rendering disabled. About -7%.
2. Ranges within a scanline (decision 75), with the dot clock the renderer moves for the board's A12 watch. About
   -7%.
3. Whole tiles unrolled (decision 76). About -15%.

**Not kept:** a whole tile as a `while` loop with the pixel inline and a `case` for the fetches. It measured about 48
ms against 40 for the per-dot path it replaced, though it calls fewer methods: YJIT runs the straight-line sequence
of calls faster.

**YJIT stays the default** (27.9 against 19.4 fps under ZJIT).

**The gap: 35.8 ms per frame under YJIT against 16.6 ms**, about 19 ms. Per component, from vernier (200 frames,
every method grouped by a pattern on its name):

| Component | Share | ms per frame |
|---|---|---|
| Pixel composition (`Renderer#run_tile` and `#draw`, the shift registers, `Picture#draw`, palette RAM, the multiplexer) | ~29% | ~10 |
| APU and audio (catch-up per cycle, channel outputs, mixer, resampler) | ~21% | ~7.5 |
| Background fetches and v updates (fetcher, `PpuBus`, nametables, mapper, MMC3's A12 watch) | ~17% | ~6 |
| The loops (`Console#run_frame`, `Ppu#catch_up`, `Renderer#run_dots` and `#run_dot`, the frame timing) | ~13% | ~4.5 |
| Sprite steps (`SpriteRenderer#run_steps` on dots 257-320, evaluation) | ~9% | ~3.5 |
| CPU and CPU bus | ~8% | ~3 |

The loops went from about 11 to about 4.5 ms. No single component closes the rest. The pixel is the largest: one
`draw` and one `Picture#draw` per pixel, 61 440 a frame. The APU's catch-up after every step is next: it runs every
CPU cycle with the channels' timers, and deferring it needs deadlines of its own for the DMC's stolen cycles and the
frame IRQ.

### Plan 25: whole frames (2026-11-22)

The frame workload (`rake bench:frames`, `bench/frame.rb`): Super Mario Bros. 3 from power-up, played by the console
spec's input script (`spec/fixtures/smb3_world_1_1.yml`) into world 1-1 with audio at 48 kHz drained every frame, 1200
warm-up frames, then 5 runs of 60 frames; frames per second is the median run. Each run prints the SHA-256 of the last
frame and of the audio, the same for every configuration and for every optimisation kept (plan 25, decisions 3 and 4).

| Configuration | Baseline (818529a) | Final | Change |
|---|---|---|---|
| interpreter | 4.3 fps (230.5 ms) | 5.2 fps (192.1 ms) | -17% per frame |
| yjit | 14.2 fps (70.3 ms) | 23.4 fps (42.7 ms) | -39% per frame |
| zjit | 12.7 fps (78.9 ms) | 15.4 fps (65.1 ms) | -17% per frame |

**Kept:** step 1, flag tests inline on hot paths (architecture decision 72, -23% under YJIT); step 2, the renderer as a
per-dot pipeline (decision 73, a further -19%). **Not kept:** grouping `run_dot`'s flag tests by stage (no gain in a
prototype). **Not done** (plan 25, decision 9): the APU, OAM DMA, CPU and frontend items of the list, each a few percent
of the frame at most, and running ranges of dots per call, which is plan 28.

**Default JIT: YJIT stays.** With whole frames it leads ZJIT by 52% (23.4 against 15.4 fps).

**The gap: 42.7 ms per frame under YJIT against 16.6 ms**, about 26 ms. Per component, from `rake bench:profile`
(vernier, 200 frames; the top 40 methods, about 90% of the samples, grouped by hand):

| Component | Share | ms per frame |
|---|---|---|
| The loop around each dot (`Ppu#catch_up`, `FrameTiming#advance`, `RenderSchedule#steps`, `Renderer#run_dot`) | ~26% | ~11 |
| Background fetches and v updates (fetcher, `PpuBus`, nametables, mapper, MMC3's A12 watch) | ~19% | ~8 |
| Pixel composition (`Renderer#draw`, the shift registers, `Picture#draw`, palette RAM) | ~17% | ~7 |
| APU and audio (catch-up per cycle, channel outputs, mixer, resampler) | ~14% | ~6 |
| CPU, CPU bus and the console loop | ~9% | ~4 |
| Sprite steps (`SpriteRenderer#run_steps` on dots 257-320, evaluation) | ~7% | ~3 |

The frontend is not in this workload (headless, no RGB conversion): in the window it adds the RGB conversion plan 16
measured at about 2.8 ms per frame, and the present.

The loop around each dot alone is about two thirds of the budget: no change inside a dot reaches 60 fps, which is why
the next step, plan 28, runs ranges of dots per call between the sync points (see above).

**`rake bench:cpu` no longer measures the CPU alone.** It reads 4.3 MHz under YJIT on 818529a and on plan 25's tree
alike, against 16.4 at the end of plan 10: since plan 22, nestest's writes to `$4015` and `$4017` catch the APU up,
and vernier puts about 60% of the workload in `Apu#catch_up` and the channels' timers. The variants' relative changes
still compare like with like (the same session, the same workload); `interrupt_poll_inline` now measures +5.5% under
YJIT and +10.7% under ZJIT, and `bits_helpers` +0.5% under YJIT, both on a workload the APU dominates.

### Plan 10: the CPU alone

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

**Board window table (architecture decision 46): kept.** Plan 19 reads PRG ROM through `Mappers::Base`'s window
offsets instead of NROM's single mask. Alternating runs in one session put its cost at about 3% under YJIT and the
interpreter and under 1% under ZJIT, below the 6% the base commit itself moved between rounds (2026-11-20 section).

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

### 2026-11-20 — Plan 19: the board's window table (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

Four `rake bench:cpu` runs in one session, merged by hand, alternating the base commit of plan 19 (361443a, NROM's
single mask `@prg_rom[address & @prg_rom_mirror_mask]`) and plan 19 (`Mappers::Base`'s window table,
`@prg_rom[@prg_window_offsets[window] + (address & PRG_WINDOW_OFFSET_MASK)]`, architecture decision 46). The change
column compares each plan 19 row with the base commit run just before it, under the same configuration.

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | base commit, round 1 | 2.89 | 162% | 8.0% | — |
| yjit | base commit, round 1 | 14.23 | 795% | 3.3% | — |
| zjit | base commit, round 1 | 7.99 | 447% | 2.1% | — |
| interpreter | window table, round 1 | 2.91 | 162% | 1.1% | +0.7% |
| yjit | window table, round 1 | 14.47 | 808% | 0.9% | +1.7% |
| zjit | window table, round 1 | 8.12 | 454% | 0.3% | +1.6% |
| interpreter | base commit, round 2 | 3.20 | 179% | 0.5% | — |
| yjit | base commit, round 2 | 15.09 | 843% | 0.7% | — |
| zjit | base commit, round 2 | 8.36 | 467% | 0.9% | — |
| interpreter | window table, round 2 | 2.95 | 165% | 2.5% | -7.8% |
| yjit | window table, round 2 | 13.95 | 779% | 0.2% | -7.6% |
| zjit | window table, round 2 | 8.11 | 453% | 0.2% | -3.0% |

The two rounds disagree in sign: the base commit alone moved 6% between them (YJIT 14.23 → 15.09), as much as the
effect measured. Averaged, the window table costs about 3% under YJIT (14.66 → 14.21) and the interpreter (3.05 →
2.93) and under 1% under ZJIT (8.18 → 8.12); two earlier runs of the same day, before and after the change, read 14.07
and 13.12 under YJIT. The cost stays under the machine's run-to-run variation; plan 25 measures whole frames, where
the PPU dominates.

### 2026-11-20 — Plan 20: two 4 KiB CHR windows (headless frames, `sprite_hit_tests_2005.10.05/01.basics.nes`)

`rake bench:cpu` runs nestest on the CPU alone and never reads CHR, so the cost of the CHR window table (architecture
decision 50, `@chr[@chr_window_offsets[window] + (address & CHR_WINDOW_OFFSET_MASK)]` instead of
`@chr[@chr_bank_offset + address]`) was measured on whole frames: a script in the session's scratch directory built a
console headless, ran 60 warm-up frames, then timed 200 frames, best and median of 3 runs per configuration. The base
commit of plan 20 (d5266f2) ran from a separate worktree, alternated with plan 20's tree in two rounds. Plan 20's tree
also carries the read-modify-write double write (decision 48), which this ROM's frames barely execute.

| Configuration | Variant | Best fps | Median fps | Change in the median |
|---|---|---|---|---|
| yjit | base commit, round 1 | 14.0 | 13.7 | — |
| yjit | plan 20, round 1 | 13.5 | 13.0 | -5.1% |
| zjit | base commit, round 1 | 14.5 | 13.9 | — |
| zjit | plan 20, round 1 | 14.5 | 13.8 | -0.7% |
| yjit | base commit, round 2 | 13.7 | 13.6 | — |
| yjit | plan 20, round 2 | 13.1 | 12.7 | -6.6% |
| zjit | base commit, round 2 | 14.2 | 13.4 | — |
| zjit | plan 20, round 2 | 14.7 | 13.7 | +2.2% |

Both rounds agree: about 5% under YJIT, nothing measurable under ZJIT. An earlier pair of runs in the same session,
with the machine less loaded, read 20.2 → 19.0 fps (median, YJIT) and 4.2 → 4.4 fps without a JIT. Dropping the
`& CHR_WINDOW_SELECT_MASK` (the PPU bus only hands `$0000-$1FFF`) moved YJIT within noise (19.1 → 19.35), so the
bit-field form stays, alike on the PRG and CHR paths. Plan 21 refines the windows to 1 KiB and plan 25 measures the
whole frame.

### 2026-11-21 — Plan 21: 8 KiB / 1 KiB windows and MMC3's A12 watch (headless frames)

A script in the session's scratch directory built a console headless, ran 60 warm-up frames, then timed 200 frames,
best and median of 3 runs per configuration (as plan 20). The windows (architecture decision 52) were measured with
`sprite_hit_tests_2005.10.05/01.basics.nes` (NROM), the base commit of plan 21 (a53eb27) from a separate worktree
alternated with plan 21's tree in two rounds; plan 21's tree also carries the register sync before mapper writes and v
shown on the PPU bus after PPUADDR and PPUDATA, which this ROM's frames barely reach.

| Configuration | Variant | Best fps | Median fps | Change in the median |
|---|---|---|---|---|
| yjit | base commit, round 1 | 18.6 | 18.6 | — |
| yjit | plan 21, round 1 | 18.1 | 18.1 | -2.7% |
| zjit | base commit, round 1 | 20.5 | 18.8 | — |
| zjit | plan 21, round 1 | 19.8 | 18.4 | -2.1% |
| yjit | base commit, round 2 | 19.0 | 19.0 | — |
| yjit | plan 21, round 2 | 18.3 | 18.3 | -3.7% |
| zjit | base commit, round 2 | 20.9 | 19.1 | — |
| zjit | plan 21, round 2 | 19.7 | 18.3 | -4.2% |

The A12 watch (decision 54, `Mmc3#ppu_read` handing every pattern fetch to `Mmc3::A12Watcher`) was measured on Super
Mario Bros. 3's title screen, plan 21's tree against the same tree with `Mmc3#ppu_read` removed in the benchmark
process (the base's read, no watch).

| Configuration | Variant | Best fps | Median fps | Change in the median |
|---|---|---|---|---|
| yjit | A12 watch, round 1 | 16.6 | 16.5 | -1.2% |
| yjit | no watch, round 1 | 16.8 | 16.7 | — |
| zjit | A12 watch, round 1 | 18.4 | 17.4 | -3.3% |
| zjit | no watch, round 1 | 19.1 | 18.0 | — |
| yjit | A12 watch, round 2 | 16.4 | 16.3 | +0.6% |
| yjit | no watch, round 2 | 16.2 | 16.2 | — |
| zjit | A12 watch, round 2 | 18.1 | 17.0 | -5.0% |
| zjit | no watch, round 2 | 19.2 | 17.9 | — |

The finer windows cost about 3% under both JITs, within the run-to-run variation plans 19 and 20 saw; the A12 watch is
within noise under YJIT and costs 3-5% under ZJIT. Neither calls for the dot-260 shortcut; plan 25 measures the whole
frame.

### 2026-11-22 — Baseline (base commit 818529a) — Super Mario Bros. 3, world 1-1 with audio, 1200 warm-up frames and 5 runs of 60

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Frames per second | ms per frame | % of real time | Spread | Frame digest | Audio digest |
|---|---|---|---|---|---|---|
| interpreter | 4.3 | 230.5 | 7% | 2.2% | f0903fbc59bf | 10369a5b40df |
| yjit | 14.2 | 70.3 | 24% | 2.8% | f0903fbc59bf | 10369a5b40df |
| zjit | 12.7 | 78.9 | 21% | 2.2% | f0903fbc59bf | 10369a5b40df |

### 2026-11-22 — Plan 25, step 1: inline flag tests on hot paths (A/B against 818529a)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

`bench/frame.rb` with its defaults (Super Mario Bros. 3, world 1-1 with audio, 1200 warm-up frames and 5 runs of 60),
the base commit from a git worktree with the same benchmark copied in, alternated with the working tree in two rounds.
Every `anybits?`/`nobits?`/`allbits?` on the hot paths became `(value & FLAG) != 0` (architecture decision 72). Every
run's digests were f0903fbc59bf (frame) and 10369a5b40df (audio), the baseline's.

| Configuration | Variant | Frames per second | ms per frame | Spread | Change in ms per frame |
|---|---|---|---|---|---|
| yjit | base commit, round 1 | 14.1 | 70.9 | 1.5% | — |
| yjit | inline flag tests, round 1 | 18.3 | 54.5 | 3.8% | -23.1% |
| zjit | base commit, round 1 | 12.8 | 78.1 | 1.7% | — |
| zjit | inline flag tests, round 1 | 14.5 | 68.8 | 2.2% | -11.9% |
| yjit | base commit, round 2 | 14.1 | 70.8 | 1.0% | — |
| yjit | inline flag tests, round 2 | 18.3 | 54.7 | 1.2% | -22.7% |
| zjit | base commit, round 2 | 12.1 | 82.7 | 29.9% | — |
| zjit | inline flag tests, round 2 | 12.0 | 83.6 | 5.4% | +1.1% |

Kept: about -23% of the frame's time under YJIT, more than the renderer alone measured in the plan's review (-15%),
since the CPU's status flags, the APU and the mappers are converted too. ZJIT's second round is noise (a 30% spread in
the base run).

### 2026-11-22 — Plan 25, step 2: the renderer as a per-dot pipeline (A/B against 818529a)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

The same procedure as step 1, the working tree carrying both steps (architecture decisions 72 and 73): the renderer
owns the background shift registers, composes each pixel in one method from the sprite line's entries, asks the
priority multiplexer only where both layers are opaque, and the picture reads palette RAM directly. Every run's digests
were the baseline's.

| Configuration | Variant | Frames per second | ms per frame | Spread | Change in ms per frame |
|---|---|---|---|---|---|
| yjit | base commit, round 1 | 13.9 | 71.9 | 1.6% | — |
| yjit | steps 1 and 2, round 1 | 22.5 | 44.3 | 0.5% | -38.4% |
| zjit | base commit, round 1 | 12.7 | 78.8 | 2.7% | — |
| zjit | steps 1 and 2, round 1 | 15.5 | 64.5 | 0.7% | -18.1% |
| yjit | base commit, round 2 | 14.6 | 68.7 | 0.6% | — |
| yjit | steps 1 and 2, round 2 | 22.8 | 43.9 | 1.9% | -36.1% |
| zjit | base commit, round 2 | 12.7 | 79.0 | 0.9% | — |
| zjit | steps 1 and 2, round 2 | 15.8 | 63.3 | 0.9% | -19.9% |

Kept: step 2 alone takes the frame from about 54.5 ms (step 1) to 44.1 ms under YJIT, -19%. A first version that kept
one private method per stage (the background pixel, the layer choice) measured only -8% (50.0 ms); folding them into
one `draw` gave the rest. A throwaway prototype that also grouped the flag tests of `run_dot` by stage showed no gain
from the grouping alone (52.2 → 55.4 ms, noise), so it was not kept.

### 2026-11-22 — Final (plan 25) — Super Mario Bros. 3, world 1-1 with audio, 1200 warm-up frames and 5 runs of 60

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Frames per second | ms per frame | % of real time | Spread | Frame digest | Audio digest |
|---|---|---|---|---|---|---|
| interpreter | 5.2 | 192.1 | 9% | 1.6% | f0903fbc59bf | 10369a5b40df |
| yjit | 23.4 | 42.7 | 39% | 0.7% | f0903fbc59bf | 10369a5b40df |
| zjit | 15.4 | 65.1 | 26% | 7.5% | f0903fbc59bf | 10369a5b40df |

### 2026-11-22 — CPU baseline (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 1.00 | 56% | 4.8% | — |
| yjit | baseline | 4.25 | 237% | 3.6% | — |
| zjit | baseline | 2.89 | 162% | 0.6% | — |

### 2026-11-22 — CPU variants (nestest, 10 M cycles, 2 warm-up and 5 measured runs)

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
|---|---|---|---|---|---|
| interpreter | baseline | 1.05 | 59% | 0.0% | — |
| interpreter | dispatch_lambda_table | 1.08 | 61% | 0.1% | +2.8% |
| interpreter | memory_string | 1.09 | 61% | 0.2% | +3.0% |
| interpreter | memory_io_buffer | 1.04 | 58% | 0.3% | -0.9% |
| interpreter | bits_helpers | 1.04 | 58% | 4.8% | -1.2% |
| interpreter | interrupt_poll_inline | 1.21 | 67% | 0.1% | +14.4% |
| yjit | baseline | 4.51 | 252% | 0.3% | — |
| yjit | dispatch_lambda_table | 4.30 | 240% | 0.2% | -4.7% |
| yjit | memory_string | 4.42 | 247% | 0.2% | -2.2% |
| yjit | memory_io_buffer | 4.11 | 230% | 0.3% | -8.9% |
| yjit | bits_helpers | 4.54 | 253% | 0.3% | +0.5% |
| yjit | interrupt_poll_inline | 4.76 | 266% | 0.2% | +5.5% |
| zjit | baseline | 2.96 | 166% | 0.2% | — |
| zjit | dispatch_lambda_table | 3.22 | 180% | 0.3% | +8.7% |
| zjit | memory_string | 2.98 | 166% | 0.2% | +0.4% |
| zjit | memory_io_buffer | 2.81 | 157% | 0.2% | -5.2% |
| zjit | bits_helpers | 2.86 | 160% | 0.1% | -3.5% |
| zjit | interrupt_poll_inline | 3.28 | 183% | 0.2% | +10.7% |

### 2026-11-22 — Plan 28: the sync deadline, ranges of dots and whole tiles (A/B against 370614b)

Super Mario Bros. 3, world 1-1 with audio, 1200 warm-up frames and 5 runs of 60, YJIT, `bench/frame.rb` run in turn
on a worktree of 370614b and on the working tree, three rounds:

| Round | 370614b | Plan 28 |
|---|---|---|
| 1 | 42.5 ms | 36.1 ms |
| 2 | 44.6 ms | 35.9 ms |
| 3 | 44.5 ms | 35.7 ms |

Every run's digests were f0903fbc59bf (frame) and 10369a5b40df (audio). The prototypes that chose the design
(monkeypatches over 370614b, one session, YJIT, about 46 ms for the base) measured:

- sync deadline: ~43 ms;
- + ranges: ~40 ms;
- + whole tiles unrolled: ~34 ms;
- whole tiles as an inline loop instead: ~48 ms.

### 2026-11-22 — Final (plan 28) — Super Mario Bros. 3, world 1-1 with audio, 1200 warm-up frames and 5 runs of 60

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Frames per second | ms per frame | % of real time | Spread | Frame digest | Audio digest |
|---|---|---|---|---|---|---|
| interpreter | 7.0 | 142.3 | 12% | 2.4% | f0903fbc59bf | 10369a5b40df |
| yjit | 27.9 | 35.8 | 46% | 1.7% | f0903fbc59bf | 10369a5b40df |
| zjit | 19.4 | 51.6 | 32% | 1.1% | f0903fbc59bf | 10369a5b40df |

### 2026-11-23 — Final (plan 29) — Super Mario Bros. 3, world 1-1 with audio, 1200 warm-up frames and 5 runs of 60

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Frames per second | ms per frame | % of real time | Spread | Frame digest | Audio digest |
|---|---|---|---|---|---|---|
| interpreter | 10.2 | 97.7 | 17% | 1.4% | f0903fbc59bf | 10369a5b40df |
| yjit | 34.1 | 29.3 | 57% | 2.6% | f0903fbc59bf | 10369a5b40df |
| zjit | 30.3 | 33.0 | 50% | 1.7% | f0903fbc59bf | 10369a5b40df |

### 2026-11-23 — Final (plan 30) — Super Mario Bros. 3, world 1-1 with audio, 1200 warm-up frames and 5 runs of 60

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Frames per second | ms per frame | % of real time | Spread | Frame digest | Audio digest |
|---|---|---|---|---|---|---|
| interpreter | 14.5 | 68.8 | 24% | 2.0% | f0903fbc59bf | 10369a5b40df |
| yjit | 46.6 | 21.4 | 78% | 2.0% | f0903fbc59bf | 10369a5b40df |
| zjit | 39.5 | 25.3 | 66% | 2.0% | f0903fbc59bf | 10369a5b40df |

### 2026-11-23 — Final (plan 31) — Super Mario Bros. 3, world 1-1 with audio, 1200 warm-up frames and 5 runs of 60

ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

| Configuration | Frames per second | ms per frame | % of real time | Spread | Frame digest | Audio digest |
|---|---|---|---|---|---|---|
| interpreter | 17.2 | 58.3 | 29% | 3.3% | f0903fbc59bf | 10369a5b40df |
| yjit | 61.5 | 16.3 | 102% | 2.4% | f0903fbc59bf | 10369a5b40df |
| zjit | 44.5 | 22.5 | 74% | 2.9% | f0903fbc59bf | 10369a5b40df |
