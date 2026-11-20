# Backend comparison: raylib vs SDL3

Plan 17 ran the same emulator behind two minimal windowed frontends, `Frontends::Raylib` and `Frontends::Sdl3`, to
choose the backend of the interactive frontend (plan 18) and of the audio output (plan 24) with evidence. Both honour
the plan 16 contract (`Frontends::Base`) and run through the same `Frontends::Driver`.

Measured on 2026-11-19, ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24], an Intel Mac, macOS 15
(Darwin 24.6.0).

## Matrix

| Criterion | raylib (`raylib-bindings` 0.8.4) | SDL3 (`sdl3-bindings` 1.0.4) |
|---|---|---|
| Installation | `gem 'raylib-bindings'`: FFI, a platform gem (x86_64/arm64 darwin, x86_64/aarch64 linux, x64 mingw) with raylib 6.1-dev built in. Nothing else to install. Loaded with `Raylib.load_lib(<gem>/lib/libraylib.<cpu>.dylib)`. Installed and ran on Ruby 4.0.9 at once. | `gem 'sdl3-bindings'`: FFI, pure Ruby, no native build; the SDL3 library comes from the system (`brew install sdl3`, here 3.4.20; a distribution package on Linux). Loaded with `SDL.load_lib('libSDL3.dylib')`; with `output_error: true` it warns about four inline helpers the library does not export (harmless). Installed and ran on Ruby 4.0.9 at once. |
| Present cost (median of 600 frames of nestest) | 2.95-2.96 ms, of which RGB conversion is ~2.8 ms (plan 16): texture upload and draw ~0.15 ms | 2.79-2.82 ms: upload and draw within the noise of the conversion |
| Audio API | `AudioStream`: two sub-buffers of a fixed size (`SetAudioStreamBufferSizeDefault`), refilled with `UpdateAudioStream` only when `IsAudioStreamProcessed`; data pushed while both are queued is dropped (a burst of 20 pushes in 100 ms kept 6). A callback mode exists (`SetAudioStreamCallback`), but it would run Ruby on the audio thread. | `SDL_AudioStream`: a real queue. `SDL_PutAudioStreamData` takes any amount, `SDL_GetAudioStreamQueued` tells how much is still to play, so a frontend can pace emulation by the queue (plan 24). Nothing is dropped; a dry queue plays silence. |
| Underrun in the smoke test | At ~18 fps a frame of tone (735 samples) is pushed every ~54 ms: both sub-buffers were always free (180 of 180 pushes accepted), so the stream ran dry two thirds of the time | Same rate: the queue was empty at all 180 pushes |
| Input | Polling (`IsKeyDown`), raylib key codes; gamepads built in (`IsGamepadButtonDown`). Esc closes the window by default (`SetExitKey`) | Polling (`SDL_GetKeyboardState`, scancodes: physical positions, layout-independent) after handling events (`SDL_PollEvent`); key events too; gamepads through the `SDL_Gamepad` API and its controller database |
| JIT interaction (frame time, median of 600 frames) | 162.10 ms no JIT, 54.23 ms YJIT, 53.01 ms ZJIT | 161.32 ms no JIT, 54.10 ms YJIT, 52.64 ms ZJIT |
| Maintenance | raylib: very active (35.7k stars, 11 open issues); bindings: one maintainer (vaiorabbit), last push 2026-10, tested on Ruby 4.0.5 | SDL: very active (17k stars), the standard library of emulators; bindings: the same maintainer, last release 2026-07 (SDL 3.4.12) |
| Licence | zlib (raylib and bindings) | zlib (SDL and bindings) |
| Code size | 110 lines | 112 lines |

Frame time is the emulator's: both backends add the same ~3 ms per frame, and no backend changes how a JIT runs the
core (both are FFI, a handful of calls per frame).

## Manual check

Both frontends showed nestest's menu and ran its tests from the keyboard (arrows, Enter, Right Shift), showed
`sprite_hit_tests_2005.10.05/01.basics` ("SPRITE HIT BASICS / PASSED") identically, and played the tone, chopped as
expected at ~18 frames per second.

## Decision

**raylib** (2026-11-19). Performance, input, code size and licence tie. What separated them:

- **Installation on every system.** raylib-bindings carries the library for macOS (Intel and ARM), Linux (x86_64 and
  aarch64) and Windows x64: `bundle install` is all. SDL3 comes from the system, a different step on each one, checked
  on 2026-11-19: `brew install sdl3` on macOS; `pacman -S sdl3` on Arch (extra, 3.4.20); `libsdl3-0` on Ubuntu only
  from 26.04 LTS (22.04 and 24.04 have no package, so SDL3 would be built from source); MSYS2's `mingw-w64-sdl3` or
  the release `SDL3.dll` on Windows. `Frontends::Sdl3` would also have needed to find the library on Windows and in
  Homebrew's `/opt/homebrew/lib` on ARM Macs.
- **Audio** was SDL3's advantage, but raylib's is workable for plan 24: waiting for a free sub-buffer before pushing
  the next one paces the emulator by the audio, a frame at a time; a ring buffer slices the APU's ~734.x samples per
  frame into sub-buffer-sized chunks. SDL3's queue would have been simpler.

Since the review: `Frontends::RaylibLibrary` names the gem's library file per system (`libraylib.<cpu>.dylib`,
`libraylib.<cpu>.so`, `libraylib.dll`, as the 0.8.4 platform gems ship them) and `Frontends::Raylib` raises
`LoadError` when it is missing, since raylib-bindings only warns. With the Mac's display asleep (`IODisplayWrangler`
power state 1 of 4), opening and drawing a raylib window crashes the process with a segmentation fault instead of
raising (seen on 2026-11-19 with the plan 17 prototype and the frontend alike): the window specs run only with the
display awake.

`Frontends::Sdl3` and the `sdl3-bindings` gem were removed (plan 17, decision 3); this document keeps what they
showed.

## How to reproduce

```sh
bundle config set --local with frontends
bundle install
bundle exec rake 'bench:frontends[600]'                                   # the table above (raylib alone now)
bundle exec ruby bench/frontends.rb ROM --backend raylib --tone           # a window until it closes
```
