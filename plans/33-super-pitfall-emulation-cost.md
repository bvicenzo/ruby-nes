# 33 — Super Pitfall's emulation cost

**Status:** done (2026-11-23)

**Depends on:** 32

## Goal

Find why Super Pitfall's emulation costs more a frame than Super Mario Bros. 3's under YJIT, and cut it without
changing a pixel or a sample, so it plays at 60 fps in the window too. The `rake bench:frames` digests of Super Mario
Bros. 3 (f0903fbc59bf frame, 10369a5b40df audio) and those of a Super Pitfall run taken at the start stay unchanged.

## Context

After plan 32 the window's presentation costs about 0.8 ms a frame and Super Mario Bros. 3 plays at about 60 fps with
crackle-free audio (M7). Playing Super Pitfall (the user's dump, UxROM: iNES mapper 2, 128 KiB PRG ROM, 8 KiB CHR RAM,
vertical mirroring) the window showed about 60 fps on black screens and 48-53 fps in play. Headless under YJIT,
900 warm-up frames then 3 runs of 120 with Right held after Start, it took 23.2 ms a frame against 20.7 ms for Super
Mario Bros. 3 in the same conditions (`docs/benchmarks.md`, plan 32).

## Findings (measured before building, 2026-11-23)

Work a frame, 600 frames after 900 of warm-up (Super Pitfall: Start at frame 200, Right from 600):

| A frame | Super Mario Bros. 3 | Super Pitfall |
|---|---|---|
| CPU steps | 9 383 | 9 413 |
| Whole PPU tiles | 7 288 | 4 682 |
| Forced blank dots | 1 619 | 23 968 |
| APU cycles run one by one | 304 | 4 358 (29 780 at the peaks) |

Frame by frame, the blocks of whole frames in forced blank (the black screens) take about 15.0 ms, less than play. In
play the median is 15-17 ms, with peaks of 28-37 ms, and every peak is a frame whose 29 780 APU cycles all run one by
one:

- **The triangle at period 0**, a step every CPU cycle: the game's way of silencing it (ultrasonic), which plan 23
  plays like any other period (decision 4). Its output changes every cycle, so each cycle takes the whole path: the
  quiet cycles of the six units, the cycle's run of the six units with the mix and the resampler, and the skip.
- **The noise at its shortest period**, 4 CPU cycles (7 445 changes a frame) in the sound effects, sometimes with the
  triangle at 0.

The candidates first listed are ruled out: the CHR read path is the same code for RAM and ROM (`Mappers::Base#ppu_read`;
`PpuBus#read` shows more in the profile because YJIT inlines the monomorphic mapper), the CPU steps are the same,
there are fewer tiles, and forced blank costs less than play. The 23.2 ms of plan 32 fell on runs with those sound
effects.

Prototypes (copies of HEAD; frames 721-1080 of Super Pitfall, in play; ms a frame):

| Version | Mean | Median | p90 | Max | Digests |
|---|---|---|---|---|---|
| HEAD | 17.8-18.0 | 15.6-15.8 | 26.8-27.2 | 31-37 | 0c8f391ad522 / 6759c1e3dbdd |
| A: the triangle runs between the other units' changes | 16.2-16.4 | 16.0 | 18.7-19.0 | 26-29 | unchanged |
| A + a pattern of 32 levels in the resampler at period 0 | 15.7 | 15.4 | 17.6 | 27 | unchanged |
| B: the triangle and the noise run together | 16.1 | 15.4 | 19.6 | 22.4 | unchanged |

Super Mario Bros. 3 stays at a mean of 16.1-16.5 ms on the same machine with every version, digests unchanged.

## Scope

In:

1. **An input script and a benchmark for Super Pitfall**: `spec/fixtures/super_pitfall_first_screens.yml` (Start at
   200, Right from 600), and `bench/frame.rb --rom "roms/Super Pitfall (USA).nes" --input … --warm-up-frames 720
   --frames 360 --runs 1`: 360 frames of play, with and without sound effects, as one run (consecutive runs fall on
   different parts of the game, a spread of 50%). The ROM stays local, never committed.
2. **The profile**, recorded in `docs/benchmarks.md`.
3. **Prototype B, built exactly** (decisions 1-3): the APU's runs are bounded by its slow units only, the frame counter,
   the two pulses and the DMC; within a run the fast ones, the triangle (its timer clocked every CPU cycle, periods from
   1 cycle, https://www.nesdev.org/wiki/APU_Triangle) and the noise (periods from 4 CPU cycles,
   https://www.nesdev.org/wiki/APU_Noise), go clock by clock, handing the resampler the same runs of levels, in the same
   order, as cycle by cycle would. A pulse cannot change every few cycles: below a period of 8 the sweep mutes it
   (https://www.nesdev.org/wiki/APU_Sweep).

Out:

- Forced blank: measured, and the black screens are already the cheapest frames.
- The pattern of 32 levels in the resampler (prototype A): about 0.5 ms more only on frames with the triangle at 0 and
  the noise silent, and it puts the triangle's sequence inside the resampler.
- Accuracy shortcuts (architecture decision 77); the window and the frame buffer contract (plan 32).

## Decisions

1. **A collaborator, `Apu::FastChannels`, runs the triangle and the noise through a quiet run.** The spec tree of
   `Apu#catch_up` with the run inside came to 27 leaves, 6 levels deep: it bounds the runs by the slow units, merges the
   fast channels' clocks, and hands the parts to the resampler. Keeping it in one unit would be worth it only for
   performance, and the split costs one call per run (a few hundred a frame), not one per clock. The APU reads the
   outputs of the pulses and the DMC once per run and hands them over; the collaborator mixes with `Mixer.mix`, whose
   contract does not change. The triangle and the noise get a small public API for it (the ticks between their clocks,
   a clock, and a skip that leaves the timer where the ticks would without clocking), instead of the prototype's
   reaching into their timers.
2. **`Audio::Resampler#add_run` takes runs of any length**: 0 cycles add nothing and 1 cycle goes as `add` does (the
   same float additions), so the fast channels always hand `add_run` and the length is decided in one place.
3. **Exactness is proven by the specs** (the levels and runs handed to a resampler when the triangle or the noise
   clocks inside a quiet run, and both on the same cycle) and by the digests of both games.

## Tasks

- [x] Super Pitfall input script and benchmark, its starting digests recorded.
- [x] Profile both games; record the parts that differ.
- [x] The triangle's and the noise's run API, test first.
- [x] `Audio::Resampler#add_run` for runs of 0 and 1 cycles, test first.
- [x] `Apu::FastChannels`: the triangle and the noise clock by clock through a quiet run, test first.
- [x] The APU's runs bounded by the slow units, handing each run to the fast channels, test first.
- [x] Play Super Pitfall in the window under YJIT: the frame rate and the audio (the frame rate measured by part in a
      hidden window; the audio's samples are bit-identical to before, so only the frame rate could make it crackle).
- [x] Record in `docs/benchmarks.md` and `docs/architecture.md`.

## Acceptance criteria

- [x] Super Mario Bros. 3's `rake bench:frames` digests unchanged (f0903fbc59bf / 10369a5b40df), and Super Pitfall's
      `bench/frame.rb` digests (720 + 360 frames) unchanged from the start (0c8f391ad522 / 6759c1e3dbdd).
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green (2850 examples; the 19 raylib window examples run on their own
      with the display awake).
- [x] Super Pitfall's mean in play no higher than Super Mario Bros. 3's, and its worst frame under about 23 ms
      headless, recorded in `docs/benchmarks.md`.
- [x] Super Pitfall in the raylib window at 60 fps under YJIT with audio free of crackles, or the remaining gap
      quantified per component.

## What was done

- **The cause found:** in Super Pitfall's sound effects the triangle plays at period 0 (a clock every cycle, the way
  games silence it) and the noise at its shortest period (every 4 cycles); each clock cut the APU's run of quiet cycles,
  so those frames ran all 29 780 APU cycles one by one (25-37 ms against about 15). Not the CHR RAM path, the sprites,
  the CPU nor forced blank, all measured.
- **`Apu::FastChannels`:** only the slow units (the frame counter, the pulses, the DMC) bound `Apu#catch_up`'s runs
  now; the triangle and the noise go through each run clock by clock, from their `quiet_ticks` every
  `ticks_per_clock`, and hand the resampler the run in parts, a mix per clock, the same parts cycle by cycle would
  give. The triangle and the noise got `ticks_per_clock` and `skip_without_clocking` (`Timer#ticks_per_clock`), the
  noise `step`; `Audio::Resampler#add_run` takes one-cycle parts straight to `#add`.
- **Exactness:** the digests of Super Mario Bros. 3 (`rake bench:frames`, all three configurations) and of Super
  Pitfall (`spec/fixtures/super_pitfall_first_screens.yml`, 720 + 360 frames) are unchanged; `FastChannels`' spec runs
  a real triangle at period 0 and a real noise at 4 cycles against the same channels cycle by cycle, samples equal to
  the last bit.
- **Measured** (`docs/benchmarks.md`): Super Pitfall in play went from a mean of 16.7 to 14.4 ms headless, p90 25.2 to
  16.6, worst frame 28-30 to 18, now below Super Mario Bros. 3's mean; in a hidden raylib window from 52 to 59.8-60.4
  fps, the emulation at 15.6 ms and `present` at 1.0 ms, a few isolated frames of 28-30 ms left.
- **Review:** no correctness finding; the reviewer's differential fuzz (the APU against one running every cycle, random
  writes to $4000-$4017, split catch-ups) found no difference in 3 200 seeds. Applied: stale comments and docs, clearer
  names in `FastChannels`, no empty part handed when a clock falls on a run's first cycle, the real-channel example, and
  a note that a `FastChannels` given to the APU must share its resampler. Not applied: splitting the stepping from the
  mixing (a mix per part with audio off), and handing `FastChannels` the get ticks the APU already counted (it keeps its
  API self-contained).
- **Environment:** the raylib window specs segfault while the machine's display sleeps, on a clean HEAD too; they pass
  with the display awake.

## References

- APU Triangle — https://www.nesdev.org/wiki/APU_Triangle
- APU Noise — https://www.nesdev.org/wiki/APU_Noise
- APU Sweep — https://www.nesdev.org/wiki/APU_Sweep
- UxROM — https://www.nesdev.org/wiki/UxROM
- CHR RAM — https://www.nesdev.org/wiki/CHR_ROM_vs._CHR_RAM
- iNES header — https://www.nesdev.org/wiki/INES
