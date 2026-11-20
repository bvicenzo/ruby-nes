# 18 — Interactive frontend and CLI

**Depends on:** 17

## Goal

A usable emulator window on raylib, the backend chosen in plan 17: correct frame pacing, configurable keys,
pause/reset, an FPS readout, and a CLI that selects the JIT. Milestone M4: an NROM game is playable.

## Context

NTSC runs at ~60.0988 frames per second. Without audio (until plan 24) pacing is timer-based: sleep until the next
frame deadline, never accumulate drift. If the emulator is slower than real time it should run as fast as it can and
show the real FPS, not stutter.

From plan 17: `Frontends::Raylib` (`lib/ruby/nes/frontends/raylib.rb`, the `raylib-bindings` gem in the optional
`frontends` Gemfile group, loaded only by frontend code) already opens a 3× window, presents the frame as an RGB24
texture, maps the keyboard to the first controller through `Frontends::Keyboard` (raylib key codes to
`Input::Controller::BUTTONS` names; the config file of this plan feeds it), and closes on the window's close button.
It runs without vsync or pacing. Things to know when building on it:

- raylib closes the window on Esc by default (`SetExitKey`, "default is ESC"); if Esc pauses or quits on purpose,
  call `SetExitKey(KEY_NULL)` and handle it here.
- With the display asleep, opening or drawing a raylib window crashes the process (a segmentation fault, not an
  exception; docs/backend-comparison.md).
- raylib's own frame limiter, `SetTargetFPS`, takes an integer (60, not NTSC's 60.0988); the pacing of this plan
  stays its own (drift correction, no catch-up burst), so leave the limiter off.
- `bench/frontends.rb ROM --backend raylib` runs a ROM in the window and `rake bench:frontends` measures it
  (docs/backend-comparison.md: ~3 ms per present, of which ~2.8 ms is RGB conversion; ~18 frames per second on
  nestest under YJIT). The CLI of this plan replaces `bench/frontends.rb` for playing; the benchmark stays.

Ruby 4.0.9 can enable a JIT at runtime (`RubyVM::YJIT.enable`, and ZJIT can be started disabled with
`--zjit-disable` for lazy enabling via `RubyVM::ZJIT.enable`), so the CLI can choose it; verify both calls on 4.0.9
before relying on them.

## Scope

In:

- Window with integer scaling, aspect option (8:7 pixel aspect vs square pixels), overscan crop option.
- Keyboard mapping with defaults (arrows, Z = B, X = A, Enter = Start, Right Shift = Select) and a config file
  (`~/.config/ruby-nes/config.yml`); opposite directions filtered here (plan 15, decision 2: the core does not
  filter them).
- Keys: pause, reset, quit, toggle FPS overlay (or window-title FPS).
- Frame pacing with drift correction.
- CLI: `ruby-nes ROM [--scale N] [--jit=none|yjit|zjit] [--headless …]`. Plan 16 built `Ruby::Nes::CommandLine` and
  `CommandLine::Options` (`--headless`, `--frames`, `--screenshot FRAME:PATH`, `--input SCRIPT`; without
  `--headless` it stops with a message): extend them, and run the window through `Frontends::Driver`. The pacing
  belongs to the windowed frontend (e.g. in `present` or `running?`), so the driver stays the same for every
  frontend.

Out: audio (plan 24), save states (backlog).

## Open decisions

- Default JIT for the CLI: YJIT, plan 10's winner (decision 19 of `docs/architecture.md`; revisit after plan 25).
- Gamepad support now or later. Recommendation: later; raylib has it built in (`IsGamepadButtonDown`), so it may be
  trivial.

## Tasks

- [ ] Specify and test the pacing logic in isolation (fake clock): on time, late by less than a frame, late by many
      frames (no catch-up burst).
- [ ] Specify and test key mapping and config loading (missing file, unknown key name, partial config).
- [ ] Specify and test CLI parsing (JIT selection, invalid values).
- [ ] Wire the frontend; manual play test.

## Acceptance criteria

- [ ] Running an NROM game (a dump the user owns, or a freely distributable homebrew NROM game) is playable with the
      keyboard.
- [ ] Measured FPS is shown; on a machine fast enough it holds 60 ± 1 without drift over 5 minutes.
- [ ] `--jit` selects the JIT and the choice is visible (`RubyVM::YJIT.enabled?` / ZJIT equivalent in the overlay or
      log).
- [ ] 100% branch coverage on pacing, mapping and CLI code; rubocop clean.

## References

- Cycle reference chart (frame rate) — https://www.nesdev.org/wiki/Cycle_reference_chart
- Overscan — https://www.nesdev.org/wiki/Overscan
- Standard controller — https://www.nesdev.org/wiki/Standard_controller
- `RubyVM::YJIT` — https://docs.ruby-lang.org/en/master/RubyVM/YJIT.html
