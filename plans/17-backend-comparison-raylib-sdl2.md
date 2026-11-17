# 17 — Backend comparison: raylib vs SDL2

**Depends on:** 14, 15, 16

## Goal

Choose the windowed backend with evidence, as late as possible: implement a minimal frontend on each candidate behind
the plan 16 contract, run the same ROM on both, compare, decide.

## Context

Candidates:

- **raylib** via `raylib-bindings` — window, texture, input and audio streams in one simple API.
- **SDL2** via `ruby-sdl2` — the de facto standard in emulators; queue-based audio fits an APU well.

Things to verify, not assume (Ruby 4.0.9 is recent; native extensions and FFI bindings may lag): installation on macOS
(Homebrew libraries, native extension build), maintenance status, and whether SDL3 has usable Ruby bindings yet.

## Scope

In:

- `Frontends::Raylib` and `Frontends::Sdl2`, each minimal: window at 3× scale, present the frame buffer as a texture,
  keyboard → controller 1, quit on window close, and an audio smoke test (a 440 Hz square wave pushed through the
  library's streaming API).
- Both libraries in an optional Gemfile group so the core never requires them.
- `docs/backend-comparison.md` with the matrix below and the decision.

Comparison matrix:

| Criterion | How it is measured |
|---|---|
| Installation | steps from a clean machine; native build or prebuilt; Ruby 4.0.9 compatibility |
| Present cost | ms per frame for RGB conversion + texture upload + draw (median over 600 frames) |
| Audio API | push/queue vs callback; underrun behaviour of the smoke test |
| Input | key events vs polling; gamepad support |
| JIT interaction | frame time under no JIT / YJIT / ZJIT (FFI calls vs C extension) |
| Maintenance | last release, open issues, Ruby 4 support |
| Code size | lines in each frontend |

## Open decisions

- Keep the losing backend (optional, unmaintained by us) or delete it? Recommendation: delete; the comparison document
  keeps the knowledge.
- If neither installs cleanly on Ruby 4.0.9: fall back candidates are Gosu or direct `ffi`/`fiddle` bindings to SDL.
  Decide with the user before writing a binding.

## Tasks

- [ ] Install each library; record the steps.
- [ ] Implement both minimal frontends (no specs for library calls; a smoke spec per backend, tagged and skipped when
      the library is absent).
- [ ] Measure; fill in the matrix; present it to the user in Portuguese for the decision.

## Acceptance criteria

- [ ] Both frontends show nestest's menu and a sprite test ROM, and respond to the keyboard.
- [ ] The matrix in `docs/backend-comparison.md` is complete with numbers.
- [ ] The decision and its reasons are recorded; plan 18 is updated to name the chosen backend.

## References

- raylib-bindings — https://github.com/vaiorabbit/raylib-bindings
- raylib cheatsheet — https://www.raylib.com/cheatsheet/cheatsheet.html
- ruby-sdl2 — https://github.com/ohai/ruby-sdl2
- SDL2 audio queue (`SDL_QueueAudio`) — https://wiki.libsdl.org/SDL2/SDL_QueueAudio
- Gosu (fallback) — https://www.libgosu.org/
