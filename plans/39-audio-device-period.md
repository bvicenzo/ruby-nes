# 39 — The audio device's period on Linux

**Status:** done (2026-11-25)

**Depends on:** 24, 32

## Goal

Bring the raylib window back to about 60 fps with audio on Linux desktops whose sound goes through PulseAudio or
PipeWire's Pulse server, where it runs at 53.4 fps, and stop the silence raylib inserts there. Nothing changes on macOS
or in the emulation: the `rake bench:frames` digests (f0903fbc59bf frame, 10369a5b40df audio) stay as they are.

## Context

On the user's MacBook (Intel i5-8257U, macOS) Super Mario Bros. 3 plays at about 60 fps in the window since plan 32.
On the user's Linux laptop (Intel i7-1185G7, Hyprland, PipeWire 1.6.9 with pipewire-pulse, 48 kHz) the overlay shows
about 53 fps, although the emulation there is faster than on the Mac.

With audio the window is paced by it (plan 24, architecture decision 71): `Frontends::AudioPacing` submits each frame's
800 samples to `Frontends::RaylibAudioStream` once one of its two sub-buffers of 800 samples has been played, so the
emulator runs at the pace the device consumes the stream.

## Findings (measured before building, 2026-11-25)

Linux laptop, Ruby 4.0.10 under YJIT, Super Mario Bros. 3 world 1-1 from its input script; the window probes ran in a
hidden raylib window, 600 warm-up frames then 900 timed.

| Measurement | Result |
|---|---|
| `bench/frame.rb` headless, 1200 warm-up frames, 5 runs of 60 | 10.2 ms a frame (98 fps); the Mac's last table: 15.0 ms |
| Window, no pacing | 10.1 ms a frame (98.6 fps), `present` 0.3 ms |
| Window, timer pacing (`Frontends::FramePacing`) | 16.64 ms (60.1 fps) |
| Window, audio pacing (the default) | 18.71 ms (53.4 fps), the same with the emulation at 9.7 or 12.4 ms a frame |
| The stream alone, no emulator, a sub-buffer refilled as soon as it is played, 800 samples | 53.3 chunks/s = 42 600 samples/s, gaps of 21.3 ms |
| The same with sub-buffers of 1600, 2400 or 4096 samples | 48 000 samples/s |
| The same, 800 samples, `PULSE_LATENCY_MSEC` 5, 10, 15 or 20 | 60.0 chunks/s (48 000 samples/s) |
| `PIPEWIRE_QUANTUM=256/48000` | unchanged, 53.3 chunks/s |
| Window, audio pacing, `PULSE_LATENCY_MSEC` 10 / 20 / 25 / 30 | 60.1 / 60.1 / 53.5 / 44.5 fps |
| `ENV['PULSE_LATENCY_MSEC'] = '15'` set by Ruby before the device opens | 60.0 chunks/s |

**Cause.** Through the Pulse client the device asks for about 1024 samples at a time (21.3 ms). raylib serves a request
from the two sub-buffers only up to the first one already played; the rest of the request is zero-filled (raudio.c),
so a request fits only when the device's period plus one sub-buffer fits in both: a period of at most 800 samples.
Here each chunk of 800 samples stands for about 898 samples of real time, silence included, and the audio pacing,
which follows the device's clock, runs at 48 000 / 898 ≈ 53.4 fps. On macOS Core Audio's period is shorter, so the
same code reaches 60 fps there. PipeWire's graph quantum (256 here) does not matter; the latency the Pulse client
library (libpulse, which miniaudio loads) asks for does, and `PULSE_LATENCY_MSEC` sets it.

## Scope

In:

1. Before raylib opens the audio device, on Linux, `PULSE_LATENCY_MSEC` is set to 15 when the environment has no value
   for it (decision 2). A value the user set is kept.
2. The measurements of the findings and after the change in `docs/benchmarks.md`; the rule and its reason in
   `docs/architecture.md` (the window's audio paragraph and a decision); the variable in the README's audio notes.

Out:

- Deeper buffering in raylib (decision 4) or an audio callback.
- Backends other than Pulse/pipewire-pulse: ALSA used directly or JACK keep their own period (decision 3).
- Measuring or choosing the period at run time.

## Decisions

Settled with the user on 2026-11-25:

1. **The rule:** the device's period must fit, with one sub-buffer, in the stream's two sub-buffers of 800 samples
   (16.7 ms each): a period of at most 800 samples.
2. **`PULSE_LATENCY_MSEC` of 15 on Linux, only when unset.** 5 to 20 measured at 60 fps, 25 already at 53.5; 15 leaves
   a margin on both sides. A value already in the environment is the user's choice and is kept, even one that brings
   the drop back.
3. **Only the Pulse client is covered**, which miniaudio prefers on Linux and which PipeWire desktops serve through
   pipewire-pulse; other backends are left as they are, as a known limit.
4. **Sub-buffers of two frames: discarded.** They work with any period, but the audio pacing would release frames in
   pairs (a visible judder) and the audio's delay would double, to about 67 ms.
5. **A unit of its own, `Frontends::AudioDeviceLatency`**, loadable without the gem like `Frontends::RaylibLibrary`:
   `apply(environment:, host_os:)` holds the decision and is specified alone; `Frontends::RaylibAudioStream`, an
   adapter without specs of its own, only calls it with `ENV` and RbConfig's `host_os` before `InitAudioDevice`.

## Tasks

- [x] The audio device's latency set before the device opens, Linux only and only when unset, test first.
- [x] `Frontends::RaylibAudioStream` applies it before `InitAudioDevice`.
- [x] Measure again: the stream alone and the window with audio pacing, with and without a user value.
- [x] Record in `docs/benchmarks.md`, `docs/architecture.md` and the README.

## Acceptance criteria

- [x] Without `PULSE_LATENCY_MSEC` in the environment, the stream alone consumes 48 000 samples/s with sub-buffers of
      800 samples on the Linux laptop, and the window with audio pacing runs at about 60 fps (hidden window probe).
- [x] With `PULSE_LATENCY_MSEC` set by the user, that value is the one used.
- [x] On another operating system the environment is left untouched (spec).
- [x] `rake bench:frames` digests unchanged (f0903fbc59bf / 10369a5b40df).
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green.
- [x] Played by the user: Super Mario Bros. 3 at about 60 fps with audio free of crackles on Linux. The Mac is left
      untouched by construction (the environment is not changed off Linux, spec above); its run comes with the next pull.

## What was done

- `Frontends::AudioDeviceLatency.apply(environment:, host_os:)` sets `PULSE_LATENCY_MSEC` to 15 on Linux when the
  environment has no value for it; `Frontends::RaylibAudioStream` calls it with `ENV` before `InitAudioDevice`.
- On the Linux laptop the stream alone now consumes 48 000 samples/s and the window with audio pacing runs at
  60.1-60.2 fps (was 53.4); a user's `PULSE_LATENCY_MSEC=30` is kept and still drops to 44.5. Digests unchanged.
- The rule, the measurements and the variable are in `docs/architecture.md` (decision 106), `docs/benchmarks.md` and
  the README.
- Found on the way: plan 32's "does not link" shader spec linked on Mesa (an input no vertex shader writes is
  accepted there), so it failed on Linux. Its shader now calls a function it declares but never defines, which fails
  to link on every driver.

## References

- raylib cheatsheet (audio streams, `SetAudioStreamBufferSizeDefault`, `IsAudioStreamProcessed`) —
  https://www.raylib.com/cheatsheet/cheatsheet.html
- pipewire-pulse(1), environment variables (`PULSE_LATENCY_MSEC`, "buffering logic in libpulse", read by the client) —
  https://docs.pipewire.org/page_man_pipewire-pulse_1.html
- raylib's raudio.c (`ReadAudioBufferFramesInInternalFormat`: a stream is read up to the first sub-buffer already
  played, and the rest of the request is zero-filled) — https://github.com/raysan5/raylib/blob/master/src/raudio.c
- miniaudio (backends and periods) — https://miniaud.io/docs/manual/index.html
