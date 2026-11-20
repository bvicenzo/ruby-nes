# 17 — Backend comparison: raylib vs SDL3

**Status:** done (2026-11-19)

**Depends on:** 14, 15, 16

## Goal

Choose the windowed backend with evidence, as late as possible: implement a minimal frontend on each candidate behind
the plan 16 contract, run the same ROM on both, compare, decide.

## Context

Candidates:

- **raylib** via `raylib-bindings` (FFI) — window, texture, input and audio streams in one simple API.
- **SDL3** via `sdl3-bindings` (FFI) — SDL is the de facto standard in emulators; its audio streams fit an APU well.

The plan was written for SDL2 via `ruby-sdl2`. Found when it started (2026-11-19):

- Homebrew's SDL2 is now `sdl2-compat`, a layer over SDL3; this machine has `sdl3` 3.4.20 and `sdl2-compat` 2.32.74
  installed. `sdl3-bindings` 1.0.4 (2026-07, FFI, by the author of `raylib-bindings`) answers the plan's question
  "does SDL3 have usable Ruby bindings yet": it does. `ruby-sdl2` 0.3.7 (2026-04, C extension, LGPL) binds the legacy
  API. Decision 1.
- `raylib-bindings` 0.8.4 (2026-09) ships one gem per platform with the raylib library built in, `x86_64-darwin`
  included: no Homebrew package needed.
- Both bindings are FFI, so the "JIT interaction" row measures the frame under each JIT; there is no FFI versus C
  extension contrast left to measure.
- The gems define the top-level modules `::Raylib` and `::SDL`; inside `Ruby::Nes::Frontends` they are always written
  with the leading `::`, since `Frontends::Raylib` is our class.

From plan 16: a frontend subclasses `Frontends::Base` (`running?`, `button_states`, `present(frame_buffer)`,
`queue_audio(samples)`) and `Frontends::Driver` runs the loop (buttons to `Console#controllers`, `run_frame`,
`present(console.ppu.frame_buffer)`). The frame buffer holds pixels of 0-511 (palette index plus emphasis bits); it
is one of two arrays the PPU swaps, valid until the next frame completes: copy it if presenting is deferred.
`Frontends::Palette.rgb(frame_buffer)` turns it into RGB24, 3 bytes per pixel (about 2.8 ms per frame with or without
a JIT, plan 16 decision 4): both libraries take RGB24 textures; add RGBA only if one needs it. `Frontends::Headless`
and `exe/ruby-nes ROM --headless` are the reference run to compare against.

No vsync and no pacing here (pacing is plan 18's): the present cost measured is RGB conversion, texture upload and
draw only.

## Scope

In:

- `Frontends::Keyboard`: the mask of the controller from a key map (library key → `Input::Controller::BUTTONS` name)
  and a "is this key held?" block. Pure, shared by both backends and by plan 18's configurable keys. It does not filter
  opposite directions (plan 18 does).
- `Frontends::Raylib` and `Frontends::Sdl3`, each minimal: window at 3× scale, present the frame buffer as a streaming
  texture (RGB24 from `Frontends::Palette`), keyboard → controller 1 through `Frontends::Keyboard` (arrows, Z = B,
  X = A, Enter = Start, Right Shift = Select), quit on window close, `queue_audio(samples)` (signed 16-bit mono)
  through the library's audio stream, and `close`. Never loaded by the core.
- A measuring harness in `bench/` (decision 2): `bench/frontends.rb ROM --backend raylib|sdl3 [--frames N] [--tone]
  [--hidden]` (`--hidden` for the smoke specs, decision 4; `--frames` at least 2, so that a frame time is measured)
  (`FrontendBenchmark::SquareWave`, `::Probe`, `::Summary`, `::Options`, `::CommandLine`) and `rake bench:frontends`
  (backend × JIT, a process each). Without `--frames` it runs until the window closes (the manual check). The audio
  smoke test is a 440 Hz square wave queued through `queue_audio` every frame.
- Both libraries in an optional Gemfile group so the core never requires them (decision 5).
- `docs/backend-comparison.md` with the matrix below and the decision.

Comparison matrix:

| Criterion | How it is measured |
|---|---|
| Installation | steps from a clean machine; native build or prebuilt; Ruby 4.0.9 compatibility |
| Present cost | ms per frame for RGB conversion + texture upload + draw (median over 600 frames) |
| Audio API | push/queue vs callback; underrun behaviour of the smoke test |
| Input | key events vs polling; gamepad support |
| JIT interaction | frame time under no JIT / YJIT / ZJIT |
| Maintenance | last release, open issues, Ruby 4 support |
| Code size | lines in each frontend |

## Decisions

Settled with the user on 2026-11-19.

1. **SDL3 via `sdl3-bindings` replaces SDL2 via `ruby-sdl2`.** Reason: Homebrew's SDL2 is already a compatibility
   layer over SDL3, which is installed; `sdl3-bindings` is actively maintained; the class is `Frontends::Sdl3`.
2. **Running and measuring through `bench/frontends.rb`**, and `rake bench:frontends` running each backend under each
   JIT in a process of its own (the flags of `CpuBenchmark::Configuration::FLAGS`), as `bench:cpu` does, printing the
   table. Reason: the measurement is a benchmark; `CommandLine` stays as plan 16 left it until plan 18 adds the
   window.
3. **The losing backend is deleted** once the decision is taken. Reason: `docs/backend-comparison.md` keeps the
   knowledge and git keeps the code.
4. **One smoke spec per backend, on a hidden window**, skipped when the gem does not load (always in CI, where the
   optional group is not installed): present a frame, queue audio, close.
5. **`group :frontends, optional: true`** in the Gemfile with both gems; `bundle config set --local with frontends`
   installs them.
6. **raylib is the backend** (settled with the user after the measurements and the manual check, 2026-11-19).
   Reason: it tied SDL3 on present cost, frame time under every JIT, input and code size, and its gem carries the
   library for macOS, Linux and Windows, where SDL3 needs a system package per OS (none on Ubuntu before 26.04 LTS);
   its fixed audio sub-buffers are workable for plan 24 (wait for a free one, slice the samples into it). Details in
   `docs/backend-comparison.md`.
7. **The tone's amplitude is an option** (`Options#tone_amplitude`, 0 without `--tone`), so the harness always feeds
   the audio stream and the command line makes no decision of its own; `Bits.set_flag`, which the glossary already
   named for `set-flag`, was added for `Frontends::Keyboard`.

## Tasks

- [x] Install each library; record the steps.
- [x] `Frontends::Keyboard` and the measuring harness, test first.
- [x] Implement both minimal frontends (no specs for library calls; a smoke spec per backend, skipped when the
      library is absent); `rake bench:frontends`.
- [x] Measure 600 frames of nestest per backend and JIT; note each library's behaviour when the tone underruns (the
      emulator runs below 60 frames per second, so 1/60 s of audio per frame falls short: input for plan 24).
- [x] Fill in the matrix; present it to the user in Portuguese for the decision.
- [x] Delete the losing backend; update plan 18 (the chosen backend), `docs/architecture.md` (Frontends, Layout,
      Decisions log), `docs/GLOSSARY.md` (FFI; SDL was added and then removed with the SDL3 backend, since the glossary
      expands names the code uses and none does any more) and `plans/README.md`.

## Acceptance criteria

- [x] Both frontends show nestest's menu and a sprite test ROM (`sprite_hit_tests_2005.10.05`), and respond to the
      keyboard.
- [x] The matrix in `docs/backend-comparison.md` is complete with numbers.
- [x] The decision and its reasons are recorded; plan 18 is updated to name the chosen backend; the loser is removed.
- [x] 100% branch coverage on `Frontends::Keyboard` and the harness; smoke specs green locally; rubocop clean;
      `bundle exec rake` green (without the optional group the smoke specs are skipped).

## What was done

- Both libraries installed with `bundle install` alone on Ruby 4.0.9 (FFI, no native build); raylib-bindings ships
  raylib for each platform, SDL3 came from Homebrew. `Gemfile` group `frontends`, optional.
- `Frontends::Keyboard` (key codes to the controller mask, `Bits.set_flag`, the helper the glossary already named),
  `Frontends::Raylib` and `Frontends::Sdl3` (3× window, RGB24 texture, keyboard, audio stream, `close`), smoke specs
  on a hidden window skipped without the gem (`spec/support/frontend_libraries.rb`, tag `frontend_library:`).
- `bench/frontends.rb` and `rake bench:frontends` (`FrontendBenchmark::Probe`, `::Summary`, `::SquareWave`,
  `::Backends`, `::Options`, `::CommandLine`). 600 frames of nestest: ~3 ms per present on both (RGB conversion is
  ~2.8 ms), ~162 ms per frame without a JIT, ~54 ms with YJIT, ~53 ms with ZJIT, the same on both backends.
- Manual check by the user: nestest's menu and tests from the keyboard, `sprite_hit_tests_2005.10.05/01.basics`
  passed, the tone audible, on both. raylib chosen (decision 6), SDL3 removed; `docs/backend-comparison.md` holds the
  matrix and the reasons; plans 18 and 24 and `docs/architecture.md` (decision 40) aligned.
- Independent review: the library file per system (`Frontends::RaylibLibrary`, Windows' `libraylib.dll`), a
  `LoadError` when it is missing, the library attached once per process; `Frontends::Base#close`; the rake task reads
  only the last output line (raylib logs to standard output); `--frames` at least 2; a missing ROM ends with a
  message; one leaf per cause in the probe spec; named constants; the gem pinned to `~> 0.8.4`. Not applied: a
  default `--backend` (the harness stays ready to compare again) and helpers shared with the CPU benchmark and the
  command line (three-line private methods; sharing them would couple the bench to the core's command line).
- The window specs crash with the display asleep (a raylib segmentation fault): the last run of the fixes was made
  CI-style, without the optional group, and the window specs are to be run again with the display awake.

## References

- raylib-bindings — https://github.com/vaiorabbit/raylib-bindings
- raylib cheatsheet — https://www.raylib.com/cheatsheet/cheatsheet.html
- sdl3-bindings — https://github.com/vaiorabbit/sdl3-bindings
- SDL3 audio streams (`SDL_PutAudioStreamData`) — https://wiki.libsdl.org/SDL3/SDL_PutAudioStreamData
- SDL3 textures (`SDL_UpdateTexture`) — https://wiki.libsdl.org/SDL3/SDL_UpdateTexture
- ruby-sdl2 (discarded, decision 1) — https://github.com/ohai/ruby-sdl2
- Gosu (fallback) — https://www.libgosu.org/
