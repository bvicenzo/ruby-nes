# 29 — APU sync deadline and runs of cycles

**Status:** done (2026-11-23)

**Depends on:** 28

## Goal

Cut the APU and audio share of a frame (about 21%, about 7.5 ms of 35.8 under YJIT after plan 28) without changing
what it produces: the frame and audio digests of `rake bench:frames` stay those of plan 28 (f0903fbc59bf frame,
10369a5b40df audio).

## Context

`Console#run_frame` catches the APU up after every CPU step, and `Apu#catch_up` runs one loop iteration per CPU
cycle:

- the frame counter's tick;
- the triangle's timer;
- on even cycles, the pulse, noise and DMC timers;
- with audio on, `Mixer.mix` of the five outputs and one `Audio::Resampler#add`.

That is about 29 800 iterations a frame, each with its method calls, even when no channel's output changes for
hundreds of cycles.

Plan 28 showed the two steps that pay for the PPU (`docs/benchmarks.md`, Findings, plan 28):

1. A sync deadline. Catch a unit up only where it can affect the CPU, besides the register accesses that already sync
   it.
2. Batches between the points where something changes. The PPU's gain came mostly from running whole tiles once the
   deadline made long ranges possible. A deadline alone gave about 7%.

The APU reaches the CPU only through:

- its two interrupt flags, the frame counter's and the DMC's, which assert the IRQ line with their cycle
  (`Apu::InterruptFlag`, plan 22, decision 6);
- the DMC's sample fetches, which halt the CPU (`Dmc::MemoryReader#fill`, `Cpu#halt`, plan 23, decision 1);
- `$4015` reads and the register writes, which already catch it up through the access cycle
  (`Apu#catch_up_to_access`);
- the audio samples `Console#audio_samples` drains once per frame, so the frame must end with the APU caught up.

## Findings that reshaped the plan

Measured before starting, under YJIT, 200 frames of world 1-1 after the 1200 warm-up frames (throwaway
instrumentation, not committed):

- **The output, not the tick, is most of the cost.** vernier puts about 20% of the frame in the APU and audio, and
  about half of it in computing the mix every cycle: `Pulse#output` 2.9%, `Apu#output` 2.0%, `Mixer.mix` 1.5%,
  `Sweep#muting?` and `#target_period` 2.0%, `DutySequencer#output` 0.8%, `Noise#output` 0.7%,
  `LengthCounter#active?` 0.6%. The loop itself (`Apu#catch_up` 3.2%), `Timer#tick` 1.4%, `Resampler#add` 1.2% and
  `FrameCounter#tick` 0.7% are the rest.
- **The mix changes about 247 times a frame**, out of about 29 780 cycles.
- **Runs that end at every sequencer clock would be short.** The noise plays with period index 1 (a clock every 4
  CPU cycles) much of the time and would end about 3 370 runs a frame; the DMC, at its fastest rate (54 cycles),
  about 550. Most runs would be 2-3 cycles long.
- **Most of those clocks change nothing audible.** The noise can sound (length counter above 0 and volume above 0)
  on 4.3% of the cycles, and the DMC has a sample playing on 31%.

So the plan gains a third step: a clock that cannot change a channel's output does not end a run.

## Scope

In, each step measured A/B interleaved and kept only if it pays (plan 25, decision 4):

1. **Sync deadline.** `Apu#sync_cycle`: the first CPU cycle at whose end the APU must be caught up. It is one past the
   earliest of:
   - the cycle of the frame counter's next tick that can set the interrupt flag (mode 0, not inhibited), and, while a
     `$4017` write is pending, the cycle it takes effect on;
   - the cycle of the DMC's next sample fetch, which also bounds its interrupt, since the flag is set when the last
     byte is fetched.

   It is memoised and cleared by every catch-up, register write and reset, as `Ppu#sync_cycle` is (architecture
   decision 74); a `$4015` read changes nothing that moves it. `Console#run_frame` catches the APU up only from `Apu#sync_cycle` on, and once more after its loop,
   so the frame ends caught up. `Console#step` keeps catching up after every step.
2. **Runs of cycles inside `Apu#catch_up`.** Each unit tells how many of its ticks pass before its next change:
   - each channel's timer, until it next clocks its sequencer;
   - the frame counter, until its next step or a pending `$4017` write takes effect.

   The loop advances every unit by the shortest of those at once. Between changes the mixer's level is constant, so it
   is computed once per run and the resampler receives a run of a level instead of one call per cycle. The cycle with
   a change runs the per-cycle body of today.
3. **Muted channels do not end runs.** A channel whose clock cannot change its output reports no bound, and its skip
   still clocks its sequencer on each reload:
   - a pulse with its length counter at 0, its sweep muting it or a volume of 0;
   - the noise with its length counter at 0 or a volume of 0;
   - the triangle with its linear or length counter at 0;
   - the DMC silent, with an empty buffer and no sample playing.

   A silent DMC that may still take a byte is quiet until the clock that starts its next output cycle, not only its
   next clock: silent clocks hold the level.

   The frame counter and the target still bound every run: the quarter and half frames change those states.

Measured with `rake bench:frames` (A/B interleaved, as in plan 28) and profiled with `rake bench:profile`.

Out:

- Accuracy shortcuts (architecture decision 77). Examples: averaging the audio per sample instead of per cycle, an
  integer accumulator in the resampler, or moving a DMC fetch off its cycle. Any such change belongs to the optional
  fast mode, proposed with its measured gain and the tests it puts at risk.
- The DMC conflict on register reads (Known gaps): unchanged.

## Design notes

- **Exactness of the deadline.** Today an event on cycle F happens in the catch-up after the step that crosses F, and
  the CPU sees it from its next poll. A deadline of F + 1 keeps that: the catch-up comes after the same step, so the
  IRQ's stamp, the DMC's halt and the poll that looks back past it (`InterruptLines#poll_before_stall`) are the same.
  A console example runs a program whose frame IRQs and DMC fetches come while it touches no APU register, and checks
  that `run_frame` takes each IRQ and each stall on the same instruction as stepping does.
- **APU ticks in CPU cycles.** The pulse, noise and DMC timers tick on even CPU cycles (plan 22, decision 5). Tick j
  (from 0) counted from cycle c falls on c + (c mod 2) + 2j; n cycles from c hold (n + 1 − (c mod 2)) / 2 ticks. One
  small module answers both, for the DMC's fetch cycle and the runs.
- **The resampler's sum is a float.** Adding a level n times and adding level × n can differ in the last bits, and the
  audio digest would then change. The resampler loops over the run's cycles adding the level, as today, and finds the
  next sample's cycle from its integer phase.
- **Sample boundaries.** A run of a level may cross the end of an output sample. The resampler splits it there.
- **Hot path rules** (`docs/architecture.md`, Hot paths): no allocation per run, integers and constant tables.

## Decisions

1. **One loop that asks each unit on every run** (option a), not a scheduler keeping each unit's next-change cycle as
   state. With muted channels not ending runs, runs are long and the questions per run are few. A scheduler only if
   the loop measures slower.
2. **The resampler takes a run with a loop over its cycles**, adding the level each cycle as today, so the float sum
   is bit-for-bit the same. An integer accumulator with integer mixer tables would change the sum's rounding and the
   audio digest: a shortcut for the fast mode, not this plan.
3. **Deadline first, then runs, then muted channels**, each measured alone A/B interleaved, as plan 28 did.
4. **The end of the frame is not part of `Apu#sync_cycle`.** The APU does not know frames; `run_frame` catches it up
   once more after its loop, to the last step's end, which is the catch-up the last step made before. Not to the CPU's
   cycle: a DMC fetch in the last step's own catch-up may have halted the CPU past it, and stepping leaves that stall
   to the next step's catch-up (found by the review; catching it up made a reset right after such a frame stamp its
   `$4017` rewrite 4 cycles late).
5. **A pending `$4017` write bounds the deadline** at the cycle it takes effect on, a conservative bound recomputed
   after it; the old sequence's next interrupt step bounds it too, since it keeps counting until then.
6. **"Never" is `Apu::NEVER`, the Integer 2**60**, not `Float::INFINITY` as `Mappers::Base::NEVER`: the runs add and
   double quiet ticks on the hot path (`GetCycles.cycle_of_tick` doubles a muted channel's NEVER), and an Integer keeps
   that arithmetic in Fixnums; 2 × 2**60 still fits a Fixnum. The deadlines (`FrameCounter#next_interrupt_cycle`,
   `Apu#sync_cycle`) answer NEVER itself rather than a cycle added to it.
7. **The catch-up loop calls a method per step** (`Apu#run_cycle`, `#skip`). Under YJIT, a catch-up of thousands of
   cycles whose `while` held the cycle's body ran about half as fast per cycle as catch-ups of 3 cycles, which made the
   deadline alone 3% slower; with the body in a method both cost the same (benchmarks.md, plan 29).
8. **`InterruptFlag#inhibited?` is not needed:** the frame counter keeps the last `$4017` value, whose inhibit bit
   reaches the flag at once.
9. **A stopped triangle's timer skips without clocking** (`Timer#skip_without_clocking`): its clocks change nothing,
   and its period is often 0 (power-up), which made `Timer#skip` loop once per cycle (found by the review).
10. **The runs ask `Timer#ticks_before_next_clock`**; `#ticks_before_clock(clocks)` stays for the DMC's output cycle.

## Tasks

- [x] Re-profile (`rake bench:profile`) and confirm the APU's share before starting.
- [x] Step 1, units test first:
  - [x] `FrameCounter#next_interrupt_cycle` (no `InterruptFlag#inhibited?`, decision 8);
  - [x] APU ticks in CPU cycles (`Apu::GetCycles`);
  - [x] `Timer#ticks_before_clock`, `OutputUnit#clocks_to_output_cycle`, `Dmc#next_fetch_cycle`;
  - [x] `Apu#sync_cycle`;
  - [x] `Console#run_frame` with the APU deadline. Measured.
- [x] Steps 2 and 3, prototyped and measured first, then units test first:
  - [x] `Timer#skip`;
  - [x] each channel's `quiet_ticks` (muted channels answering `NEVER`) and `skip`, with `OutputUnit#silent?` and
        `MemoryReader#empty?`;
  - [x] the frame counter's `quiet_cycles` and `skip`;
  - [x] `Audio::Resampler#add_run`;
  - [x] `Apu#catch_up` by runs. Measured.
- [x] The whole suite and the test ROMs stay green: `apu_test` (its IRQ flag timing and DMC ROMs), `apu_reset`,
      `cpu_interrupts_v2` (`4-irq_and_dma`) and `instr_misc/04-dummy_reads_apu`. These sync through `$4015` and the
      CPU's IRQ, so a console example covers the case they do not: IRQs and DMC fetches arriving while the program
      touches no APU register.
- [x] Measure and record in `docs/benchmarks.md`, kept and not kept steps alike.
- [x] `docs/architecture.md`: APU, audio, clock model, hot paths, decisions log (78-82); `docs/GLOSSARY.md`: run,
      sync deadline.

## Acceptance criteria

- [x] `rake bench:frames` digests unchanged from plan 28 (f0903fbc59bf frame, 10369a5b40df audio) after every kept
      step.
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green (2753 examples; the raylib window specs cannot run in this
      environment, as in plans 22-28).
- [x] Each step (deadline, runs, muted channels) measured A/B interleaved and recorded in `docs/benchmarks.md`, kept or
      not.
- [x] The new frames per second recorded per configuration. One of:
  - 60 fps under one configuration with the window's audio free of crackles (M7 closes);
  - the remaining gap quantified per component.

## What was done

- **Sync deadline.** `Console#run_frame` catches the APU up from `Apu#sync_cycle` on, about 30 times a frame instead
  of about 9 900, and once more to the last step's end. `Apu#sync_cycle` is one past the earlier of
  `FrameCounter#next_interrupt_cycle` and `Dmc#next_fetch_cycle` (with `Timer#ticks_before_clock` and
  `OutputUnit#clocks_to_output_cycle`), memoised until a catch-up, register write or reset. `Apu::GetCycles` turns
  APU ticks into CPU cycles.
- **Runs.** `Apu#catch_up` skips quiet cycles at once: `FrameCounter#quiet_cycles` and `#skip`, each channel's
  `quiet_ticks` (NEVER while muted) and `skip`, `Timer#skip`, `#skip_without_clocking` and `#ticks_before_next_clock`,
  `OutputUnit#silent?`, `MemoryReader#empty?`. The mix is taken once per run; `Audio::Resampler#add_run` keeps the
  float sum bit for bit.
- **Measured** (`rake bench:frames`):

  | Configuration | Plan 28's final | Now |
  |---|---|---|
  | interpreter | 7.0 fps | 10.2 fps |
  | yjit | 27.9 fps | 34.1 fps |
  | zjit | 19.4 fps | 30.3 fps |

  Interleaved under YJIT, about 35-36 ms became about 29 ms (-19%). Frame and audio digests are unchanged.
- **A YJIT finding:** a long catch-up whose `while` held the cycle's body ran about half as fast per cycle; the bodies
  are methods of their own (decision 7).
- **The gap left:** about 12.7 ms per frame under YJIT. Per component, in `docs/benchmarks.md`: pixel ~36%, fetches
  ~22%, the loops ~15%, sprites ~10%, CPU ~7%, APU and audio ~2%. Plans 30 and 31 are next.
- **Docs.** `docs/architecture.md`: APU runs, audio, clock model step 8, hot paths, decisions 78-82;
  `docs/GLOSSARY.md`: run, sync deadline; `docs/benchmarks.md`: the findings and the kept and not kept steps.
- **Independent review.** No error in the runs' exactness. Applied:
  - the final catch-up goes to the last step's end, not past a DMC stall it added, with a console example comparing a
    reset after such a frame with stepping;
  - a stopped triangle's timer skips without a call per clock;
  - `add_run` never divides by 0 with an output rate above the input rate, through `Integer#ceildiv`;
  - `Timer#ticks_before_next_clock` instead of a constant 1;
  - decision 6's wording.

  Not changed: the mix taken at the start of each catch-up even when its first cycle recomputes it (about 30 a frame).
- Slow suite: 2761 examples, 0 failures. The raylib window specs cannot run in this environment, as in plans 22-28.

## References

- Catch-up — https://www.nesdev.org/wiki/Catch-up
- APU — https://www.nesdev.org/wiki/APU
- APU Frame Counter — https://www.nesdev.org/wiki/APU_Frame_Counter
- APU DMC — https://www.nesdev.org/wiki/APU_DMC
- APU Pulse — https://www.nesdev.org/wiki/APU_Pulse
- APU Triangle — https://www.nesdev.org/wiki/APU_Triangle
- APU Noise — https://www.nesdev.org/wiki/APU_Noise
- APU Mixer — https://www.nesdev.org/wiki/APU_Mixer
- DMA — https://www.nesdev.org/wiki/DMA
- CPU interrupts — https://www.nesdev.org/wiki/CPU_interrupts
