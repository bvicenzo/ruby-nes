# 24 — Audio output and synchronisation

**Status:** done (2026-11-22)

**Depends on:** 18, 23

## Goal

Turn the APU's per-cycle output into 48 kHz signed 16-bit samples, play them through raylib, and let audio drive the
emulator's pace; write them to a WAV file in the headless run. Milestone M6: SMB3 with sound.

## Context

- The APU produces ~1.79 million values per second; the device wants 48 000. Downsampling averages every CPU cycle of
  each output period (a box filter); better quality would come from band-limited synthesis (out of scope).
- The NES output passes through filters. The [APU Mixer](https://www.nesdev.org/wiki/APU_Mixer) page lists "A
  first-order high-pass filter at 90 Hz", "A first-order low-pass filter at 14 kHz" and "A second-order low-pass
  comfortably above the audible range and thus not needed for emulation". This plan first named a second high-pass at
  440 Hz: the page (read on 2026-11-22) does not list it, so it is not modelled.
- Pacing: with audio on, the emulator produces frames as the audio buffer drains (audio-driven sync). The audio clock is
  then the master: the emulator waits for a free sub-buffer, so production never drifts from consumption, and dynamic
  rate control (meant for a video clock as master) has nothing to correct (decision 4).
- When the emulator is slower than real time, audio underruns. raylib's `ReadAudioBufferFramesInInternalFormat`
  (`raudio.c`) stops at a sub-buffer already processed and zero-fills the rest ("Zero-fill excess"): an underrun is a
  gap of silence, never a repeat of old samples.
- Speed when this plan started: SMB3 runs at 16.1 frames per second under YJIT; mixing the five channels every CPU
  cycle measured 14.7 (about −9%). Full speed is plan 25's.
- The backend is raylib (plan 17, docs/backend-comparison.md): an `AudioStream` of two sub-buffers of a fixed size
  (`SetAudioStreamBufferSizeDefault` before the stream is loaded), refilled with `UpdateAudioStream` only when
  `IsAudioStreamProcessed`. Audio-driven pacing waits for a free sub-buffer and fills it whole: a queue slices the
  APU's ~798.7 samples per frame into sub-buffer-sized chunks. raylib's callback mode would run Ruby on the audio
  thread; not used.
- From plan 18: timer pacing is `Frontends::FramePacing`, a collaborator injected into `Frontends::Raylib` (`pacing:`)
  and called after each present; audio-driven pacing is another strategy with the same `wait` message. While paused
  the window keeps presenting the last frame (plan 18, decision 5): audio is then silent (decision 7).
- From plan 23: `Apu#output` returns the mix of the five channels (0.0-1.0) computed on demand (decision 8); the
  accumulation per CPU cycle goes in `Apu#catch_up`, with no allocation per cycle. Ultrasonic triangle periods are
  played as the hardware plays them (decision 4): listen for them (decision 8 here).

## Scope

In: box resampler, the two first-order filters, conversion to signed 16-bit, a per-frame sample buffer in the core,
the driver handing each frame's samples to the frontend, audio-driven pacing in the raylib window (timer pacing with
`--no-audio`), silence while paused, a WAV writer for the headless frontend (`--wav PATH`).

Out: band-limited synthesis (stretch goal, if quality is poor), dynamic rate control, the 60 fps crackle-free check
(plan 25, decision 3).

## Decisions

Settled with the user on 2026-11-22.

1. **48 kHz, mono, signed 16-bit PCM.** The macOS output device runs at 48 000 Hz natively (`system_profiler
   SPAudioDataType`), so miniaudio does not resample again. `Audio::SAMPLE_RATE` lives in the core, shared by the
   console, the window and the WAV writer; a raylib sub-buffer is 800 samples (48 000 / 60).
2. **Underrun is a gap of silence**, raylib's own behaviour; the frame rate overlay stays. At today's ~15 fps the music
   is choppy (about 17 ms of sound, 45 ms of silence per frame); the gaps vanish at full speed. Rejected: muting while
   slow (thresholds and state), slowing the pitch (unbounded rate control).
3. **"Plays without crackles at full speed" moves to plan 25**, the plan that reaches full speed. Plan 24 checks the
   sound through the headless WAV (right at any speed) and by ear in the window.
4. **Box resampler, no dynamic rate control.** The phase is an exact integer: the CPU clock is the master clock ÷ 12,
   and the master clock "236.25 MHz ÷ 11 by definition"
   ([Cycle reference chart](https://www.nesdev.org/wiki/Cycle_reference_chart)), so 945 000 000 / 528 Hz, reduced to
   19 687 500 / 11; each CPU cycle adds 11 × the output rate to the phase, and a sample is due each time it reaches
   19 687 500. Each sample is the mean of the levels of the cycles since the previous one.
5. **Filters: a first-order high-pass at 90 Hz, then a first-order low-pass at 14 kHz** (APU Mixer), run at the
   output rate on each sample, in the discrete RC form.
6. **No audio, no mixing:** without a sample rate (`--no-audio`, a headless run without `--wav`, specs, benchmarks)
   the APU has no resampler and `@resampler&.add(output)` skips evaluating `output`, so the cost is one nil test per
   cycle.
7. **Paused, the window queues a frame of silence per frame**: audio pacing keeps the window at the audio rate and the
   speaker is silent.
8. **Ultrasonic triangle:** listen to SMB3; silence those periods only if the resampler turns them into audible noise.
   Heard on 2026-11-22 (menu and world map music): no audible noise, so no workaround.
9. **The low-pass stays in the RC form** although it cuts more than the analogue filter near the Nyquist frequency (a
   14 kHz sine at 48 kHz comes out at 0.55 rather than 1/√2, measured); its specs check the cut-off at 100 Hz, and the
   difference is in Known gaps. Rejected: a bilinear transform with pre-warping (exact at the cut-off, two more
   coefficients, no audible gain).

## Tasks

- [x] `Audio::HighPassFilter` and `Audio::LowPassFilter` (constant input decays to 0 / passes; a sine at the cut-off
      comes out at 1/√2 of its amplitude).
- [x] `Audio::SampleBuffer` (preallocated, a frame's samples drained at once; full, it drops the new ones).
- [x] `Audio::OutputStage` (the two filters, then signed 16-bit, rounded; a 0.0-1.0 level needs no clamping).
- [x] `Audio::Resampler` (exact integer phase, mean of the period's levels).
- [x] `Apu.new(audio:)` and the accumulation in `Apu#catch_up`; `Console.new(audio_sample_rate:)` and
      `Console#audio_samples`.
- [x] `Frontends::Driver` hands each frame's samples to `queue_audio`.
- [x] `Frontends::Wav.encode` (header fields, sample format); `Frontends::Headless(wav:)` writes it on `close`;
      `--wav PATH` and `--no-audio`; a stored digest of SMB3's title music.
- [x] `Frontends::AudioPacing` (fake stream: no whole chunk, a chunk with room, a chunk waiting for room, several
      chunks, the bound on what it keeps).
- [x] Wire `Frontends::Raylib` (48 kHz, 800-sample sub-buffers, audio pacing by default, silence while paused);
      listen to SMB3's title and world 1-1.
- [x] Update `docs/architecture.md`, `docs/GLOSSARY.md`, plan 25.

## Acceptance criteria

- [x] Headless run writes a WAV of SMB3's music that sounds right (human check), with a stored digest as regression
      guard. SMB3's title screen is silent: the game first writes the channels after Start (frame 521, the menu's
      sound), and the world map music starts at frame 588, so the WAV covers the menu and the map.
- [x] In the window, SMB3 plays music and effects (with gaps of silence while below full speed, decision 2); paused it
      is silent; `--no-audio` falls back to timer pacing.
- [x] The underrun behaviour matches decision 2 and is documented.
- [x] 100% branch coverage on resampler, filters, output stage, sample buffer, WAV writer and pacing; rubocop clean.
- [x] Every test ROM that passed before still passes
      (`SLOW=1 RUBYOPT=--yjit bundle exec rspec --tag '~frontend_library'`: 2581 examples, 0 failures; rubocop clean).

## What was done

- The core: `Ruby::Nes::Audio` with `SAMPLE_RATE` (48 kHz), `BITS_PER_SAMPLE` and `CHANNELS`; `Audio::Resampler` (box
  filter, exact integer phase), `Audio::HighPassFilter` and `Audio::LowPassFilter` (discrete RC form),
  `Audio::OutputStage` (90 Hz high-pass, 14 kHz low-pass, rounded to signed 16 bits) and `Audio::SampleBuffer`
  (allocated once). `Apu.new(resampler:)` hands the mix of every CPU cycle to it (`@resampler&.add(output)`);
  `Console.new(audio_sample_rate:)` builds the chain and `Console#audio_samples` drains it once per frame.
- The frontends: `Frontends::Driver` hands each frame's samples to `queue_audio` before presenting it;
  `Frontends::Wav` encodes mono 16-bit PCM; `Frontends::Headless(wav:)` writes it on `close`, however the run ends.
  `Frontends::AudioPacing` submits every whole chunk the stream has room for when queued and waits for room after the
  present (at most `MAXIMUM_POLLS` polls), keeping at most four chunks; `Frontends::RaylibAudioStream` adapts raylib's
  two sub-buffers of 800 samples. `Frontends::Raylib` paces by audio, queues silence while paused, and falls back to
  the timer with `--no-audio` or without an audio device.
- The command line: `--wav PATH` (headless) and `--no-audio` (window); `Options#audio_sample_rate` makes the console
  mix only when the run plays or keeps the audio.
- SMB3's title screen is silent (the game first writes the channels after Start, frame 521); its menu and world map
  music were heard right in a 1200-frame WAV and in the window, and the first 720 frames' WAV digest guards it
  (`command_line_spec`, `:slow`, `local_rom:`). No audible noise from ultrasonic triangle periods (decision 8).
- `docs/architecture.md` (Audio section, frontends, layout, hot paths, Known gaps, decisions 68-71),
  `docs/GLOSSARY.md` (box filter, DC, high-pass/low-pass, Nyquist, PCM, RC, RIFF, underrun, WAV), plan 25 (the cost of
  the mix per cycle and the crackle-free check). The implement-plan skill now runs the slow suite with YJIT, as CI does.
- Independent review: applied the poll limit and the audio device check (a dead device froze the window), submitting
  on queue so the unpaced benchmark's tone plays, specs for the cut-offs, for no mixing without a resampler, for the
  WAV written when a run fails, a stricter headless example, the shared format constants, renames (`resampler:`,
  `@audio_pacing`), line breaks and reflows. Not applied: renaming the filters' `alpha`/`beta` (the RC literature's
  names), smoke specs of the raylib audio path (they cannot run here, and CI has no raylib).
- The raylib window specs crash this environment's Ruby on `CloseWindow` (as in plans 22 and 23); the suite ran with
  `--tag '~frontend_library'`: `SLOW=1 RUBYOPT=--yjit`, 2584 examples, 0 failures, 9 min 49 s.

## References

- APU Mixer (output levels and filters) — https://www.nesdev.org/wiki/APU_Mixer
- APU (mixer section: "the final signal may go through a lowpass and highpass filter") — https://www.nesdev.org/wiki/APU#Mixer
- Cycle reference chart (master and CPU clocks) — https://www.nesdev.org/wiki/Cycle_reference_chart
- Band-limited synthesis (Blip_Buffer overview) — http://www.slack.net/~ant/bl-synth/
- WAVE format (little-endian, PCM two's complement) — https://www.mmsp.ece.mcgill.ca/Documents/AudioFormats/WAVE/WAVE.html
- First-order filters, discrete-time realisation — https://en.wikipedia.org/wiki/High-pass_filter#Discrete-time_realization
  and https://en.wikipedia.org/wiki/Low-pass_filter#Discrete-time_realization
- raylib `raudio.c` (stream sub-buffers, zero-fill) — https://github.com/raysan5/raylib/blob/master/src/raudio.c
