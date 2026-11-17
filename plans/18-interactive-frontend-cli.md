# 18 — Interactive frontend and CLI

**Depends on:** 17

## Goal

A usable emulator window on the backend chosen in plan 17: correct frame pacing, configurable keys, pause/reset, an
FPS readout, and a CLI that selects the JIT. Milestone M4: an NROM game is playable.

## Context

NTSC runs at ~60.0988 frames per second. Without audio (until plan 24) pacing is timer-based: sleep until the next
frame deadline, never accumulate drift. If the emulator is slower than real time it should run as fast as it can and
show the real FPS, not stutter.

Ruby 4.0.9 can enable a JIT at runtime (`RubyVM::YJIT.enable`, and ZJIT can be started disabled with
`--zjit-disable` for lazy enabling via `RubyVM::ZJIT.enable`), so the CLI can choose it; verify both calls on 4.0.9
before relying on them.

## Scope

In:

- Window with integer scaling, aspect option (8:7 pixel aspect vs square pixels), overscan crop option.
- Keyboard mapping with defaults (arrows, Z = B, X = A, Enter = Start, Right Shift = Select) and a config file
  (`~/.config/ruby-nes/config.yml`); opposite directions filtered (plan 15 decision).
- Keys: pause, reset, quit, toggle FPS overlay (or window-title FPS).
- Frame pacing with drift correction.
- CLI: `ruby-nes ROM [--scale N] [--jit=none|yjit|zjit] [--headless …]`.

Out: audio (plan 24), save states (backlog).

## Open decisions

- Default JIT for the CLI: the winner of plan 10 (revisit after plan 25).
- Gamepad support now or later. Recommendation: later, if the backend makes it trivial.

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
