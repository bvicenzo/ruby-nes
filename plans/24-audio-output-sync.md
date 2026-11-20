# 24 — Audio output and synchronisation

**Depends on:** 18, 23

## Goal

Turn the APU's per-cycle output into 44.1/48 kHz samples, play them through the chosen backend, and let audio drive
the emulator's pace. Milestone M6: SMB3 with sound.

## Context

- The APU produces ~1.79 million values per second; the device wants 44 100 or 48 000. Downsampling needs at least
  averaging over each output period (a box filter); better quality comes from band-limited synthesis.
- The NES output passes through filters (high-pass ~90 Hz and ~440 Hz, low-pass ~14 kHz); applying them removes DC
  offset and harshness.
- Pacing: with audio on, the emulator should produce frames as the audio buffer drains (audio-driven sync), adjusting
  the resampling ratio slightly (dynamic rate control) to avoid underruns and overruns without audible pitch change.
- When the emulator is slower than real time, audio will underrun; the behaviour then must be a decision, not an
  accident.
- The backend is raylib (plan 17, docs/backend-comparison.md). `Frontends::Raylib#queue_audio` pushes signed 16-bit
  mono samples at 44.1 kHz into a raylib `AudioStream`: two sub-buffers of a fixed size (`SAMPLES_PER_FRAME`, 735,
  set with `SetAudioStreamBufferSizeDefault` before the stream is loaded), refilled with `UpdateAudioStream` only when
  `IsAudioStreamProcessed`; samples pushed while both are queued are dropped. So audio-driven pacing here means
  waiting for a free sub-buffer and filling it whole: the ring buffer slices the APU's ~734.x samples per frame into
  sub-buffer-sized chunks. raylib's callback mode (`SetAudioStreamCallback`) would run Ruby on the audio thread;
  measure it before choosing it. In plan 17's smoke test, at ~18 frames per second every push found both sub-buffers
  free: the stream ran dry two thirds of the time.
- From plan 18: timer pacing is `Frontends::FramePacing` (wait for the next deadline at 60.0988 Hz, drift corrected,
  no catch-up burst), a collaborator injected into `Frontends::Raylib` (`pacing:`) and called after each present;
  audio-driven pacing is another strategy with the same `wait` message. While paused the window keeps presenting the
  last frame (plan 18, decision 5): audio should then be silent, not underrun noise.

## Scope

In: resampler, the three first-order filters, a ring buffer between the core and the backend, audio-driven pacing
replacing timer pacing when audio is on, `--no-audio`, a WAV writer for the headless frontend.

Out: band-limited synthesis (stretch goal, if quality is poor).

## Open decisions

- Sample rate: 44.1 kHz vs 48 kHz (whichever the backend prefers natively on macOS).
- Behaviour when slower than real time: let audio crackle, drop to silence, or slow everything (pitch drop).
  Recommendation: silence on underrun plus the FPS indicator; decide after hearing it.
- Resampler: box averaging vs a simple windowed-sinc. Recommendation: box first, measure quality by ear and with a
  spectrum of a test tone.

## Tasks

- [ ] Specify and test the resampler (ratio, fractional accumulation, dynamic rate adjustment bounds).
- [ ] Specify and test the filters (DC removal: constant input decays to 0; known cut-off response at sample points).
- [ ] Specify and test the WAV writer (header fields, sample format).
- [ ] Specify and test the pacing controller (fake audio buffer: low, nominal, high levels).
- [ ] Wire into the backend; listen to SMB3's title and world 1-1.

## Acceptance criteria

- [ ] Headless run writes a WAV of SMB3's title music that sounds right (human check), with a stored digest as
      regression guard.
- [ ] Interactive SMB3 plays music and effects without crackles when the emulator runs at full speed.
- [ ] The underrun behaviour matches the decision and is documented.
- [ ] 100% branch coverage on resampler, filters, WAV writer and pacing; rubocop clean.

## References

- APU Mixer (output levels) — https://www.nesdev.org/wiki/APU_Mixer
- APU (output filtering notes) — https://www.nesdev.org/wiki/APU#Mixer
- Band-limited synthesis (Blip_Buffer overview) — http://www.slack.net/~ant/bl-synth/
- Dynamic rate control — https://docs.libretro.com/development/cores/dynamic-rate-control/
- WAV format — http://soundfile.sapp.org/doc/WaveFormat/
