# 29 — APU sync deadline and runs of cycles

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

## Scope

In:

- **`Apu#sync_cycle`**: the first CPU cycle at whose end the APU must be caught up. It is the earliest of:
  - the frame counter's next interrupt step (mode 0, not inhibited);
  - the DMC's next sample fetch, which also bounds its interrupt, since the flag is set when the last byte is fetched;
  - the end of the frame.

  It is memoised and cleared by every catch-up, register access and reset, as `Ppu#sync_cycle` is (architecture
  decision 74).
- **`Console#run_frame`** catches the APU up only from `Apu#sync_cycle` on, and at the frame's end. `Console#step`
  keeps catching up after every step.
- **Runs of cycles inside `Apu#catch_up`.** Each unit tells how many cycles pass before its next change:
  - each channel's timer, until it next clocks its sequencer;
  - the frame counter, until its next step or a pending `$4017` write takes effect;
  - the DMC, until its next fetch.

  The loop advances every unit by the shortest of those at once. Between changes, the mixer's level is constant, so
  the resampler receives a run of a level instead of one call per cycle.
- Measured with `rake bench:frames` (A/B interleaved, as in plan 28) and profiled with `rake bench:profile`.

Out:

- Accuracy shortcuts (architecture decision 77). Examples: averaging the audio per sample instead of per cycle, or
  moving a DMC fetch off its cycle. Any such change belongs to the optional fast mode, proposed with its measured gain
  and the tests it puts at risk.
- The DMC conflict on register reads (Known gaps): unchanged.

## Design notes

- **Exactness of the deadline.** Today an event on cycle F happens in the catch-up after the step that crosses F, and
  the CPU sees it from its next poll. A deadline of F + 1 keeps that: the catch-up comes after the same step. Prove the
  bound as plan 28 did. A console example runs a program whose frame IRQs and DMC fetches come while it touches no APU
  register, and checks that `run_frame` takes each IRQ and each stall on the same instruction as stepping does.
- **The resampler's sum is a float.** Adding a level n times and adding level × n can differ in the last bits, and the
  audio digest would then change. Two exact options:
  - the resampler loops over the run's cycles, which is still far cheaper than the APU loop around it;
  - an integer accumulator, which is exact only if the mixer's levels become integers (a scaled table).

  Measure both before choosing (open decision 2).
- **Sample boundaries.** A run of a level may cross the end of an output sample. The resampler splits it there.
- **The triangle at high frequencies** clocks its sequencer every few cycles, so runs can be short while it plays.
  The profile says whether that matters.
- **Hot path rules** (`docs/architecture.md`, Hot paths): no allocation per run, integers and constant tables.

## Open decisions

1. **One loop or a scheduler.**
   - (a) `Apu#catch_up` asks each unit for its cycles to the next change on every run.
   - (b) Each unit keeps its next-change cycle as state, updated when it clocks or is written.

   Recommendation: (b) if (a) measures slower, since the questions are per run.
2. **How the resampler takes a run**: a loop per cycle inside the resampler, or an integer accumulator with integer
   mixer tables (see Design notes). Recommendation: whichever keeps the audio digest and measures faster.
3. **Deadline first or both at once.** Recommendation: build the deadline first and measure it alone, as plan 28 did.
   The runs come next, in the same plan.

## Tasks

- [ ] Re-profile (`rake bench:profile`) and confirm the APU's share before starting.
- [ ] Units, test first:
  - [ ] each unit's cycles to its next change (timers, frame counter, DMC);
  - [ ] `Apu#sync_cycle`;
  - [ ] `Apu#catch_up` by runs;
  - [ ] `Audio::Resampler` taking a run;
  - [ ] `Console#run_frame` with the APU deadline.
- [ ] The whole suite and the test ROMs stay green: `apu_test` (its IRQ flag timing and DMC ROMs), `apu_reset`,
      `cpu_interrupts_v2` (`4-irq_and_dma`) and `instr_misc/04-dummy_reads_apu`. These sync through `$4015` and the
      CPU's IRQ, so a console example covers the case they do not: IRQs and DMC fetches arriving while the program
      touches no APU register.
- [ ] Measure and record in `docs/benchmarks.md`, kept and not kept steps alike.
- [ ] `docs/architecture.md`: APU, clock model, decisions log.

## Acceptance criteria

- [ ] `rake bench:frames` digests unchanged from plan 28 (f0903fbc59bf frame, 10369a5b40df audio).
- [ ] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green.
- [ ] The new frames per second recorded per configuration. One of:
  - 60 fps under one configuration with the window's audio free of crackles (M7 closes);
  - the remaining gap quantified per component.

## References

- Catch-up — https://www.nesdev.org/wiki/Catch-up
- APU — https://www.nesdev.org/wiki/APU
- APU Frame Counter — https://www.nesdev.org/wiki/APU_Frame_Counter
- APU DMC — https://www.nesdev.org/wiki/APU_DMC
- APU Mixer — https://www.nesdev.org/wiki/APU_Mixer
- DMA — https://www.nesdev.org/wiki/DMA
- CPU interrupts — https://www.nesdev.org/wiki/CPU_interrupts
