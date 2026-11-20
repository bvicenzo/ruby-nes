# 18 — Interactive frontend and CLI

**Status:** done (2026-11-20)

**Depends on:** 17

## Goal

A usable emulator window on raylib, the backend chosen in plan 17: correct frame pacing, configurable keys,
pause/reset, an FPS readout, and a command line that selects the JIT. Milestone M4: an NROM game is playable.

## Context

NTSC runs at 60.0988 frames per second ("Frame rate (vertical scan rate)", NTSC: "60.0988 Hz",
[Cycle reference chart](https://www.nesdev.org/wiki/Cycle_reference_chart)). Without audio (until plan 24) pacing is
timer-based: sleep until the next frame deadline, never accumulate drift. If the emulator is slower than real time it
runs as fast as it can and shows the real frame rate, with no catch-up burst.

From plan 17: `Frontends::Raylib` (`lib/ruby/nes/frontends/raylib.rb`, the `raylib-bindings` gem in the optional
`frontends` Gemfile group, loaded only by frontend code) already opens a 3× window, presents the frame as an RGB24
texture, maps the keyboard to the first controller through `Frontends::Keyboard` (raylib key codes to
`Input::Controller::BUTTONS` names), and closes on the window's close button. It runs without vsync or pacing.
Things to know when building on it:

- raylib closes the window on Esc by default (`SetExitKey`, "default is ESC"); Esc quits through this plan's own
  hotkeys, so the frontend calls `SetExitKey(KEY_NULL)`.
- With the display asleep, opening or drawing a raylib window crashes the process (a segmentation fault, not an
  exception; docs/backend-comparison.md).
- raylib's own frame limiter, `SetTargetFPS`, takes an integer (60, not NTSC's 60.0988); the pacing of this plan
  stays its own (drift correction, no catch-up burst), so the limiter stays off.
- `bench/frontends.rb ROM --backend raylib` runs a ROM in the window and `rake bench:frontends` measures it
  (~3 ms per present, of which ~2.8 ms is RGB conversion; **~18 frames per second on nestest under YJIT**). The
  command line of this plan replaces `bench/frontends.rb` for playing; the benchmark stays, without pacing.

Found when the plan started (2026-11-20):

- **60 frames per second is out of reach today** (~18 under YJIT, plan 17). The frame rate criterion is checked with
  the game **paused**: a paused window presents the last frame again, so a frame costs only the RGB conversion and the
  draw (~3 ms), and the pacing alone decides the rate. The pacing logic itself is specified with a fake clock. Real
  time is plan 25's.
- **A JIT can be enabled at runtime on Ruby 4.0.9**, checked: `RubyVM::YJIT.enable` and `RubyVM::ZJIT.enable` both
  work without a command-line flag (ZJIT needs no `--zjit-disable`); with one JIT on, enabling the other prints
  "Only one JIT can be enabled at the same time." and returns false; neither can be disabled.
- **Pause and reset need the console**, which a frontend does not hold: the `Frontends::Base` contract gains
  `paused?` and `reset_requested?` (false by default, so the headless frontend is unchanged) and `Frontends::Driver`
  acts on them (decision 5).
- Plan 24 replaces timer pacing with audio-driven pacing, so the pacing is a collaborator injected into
  `Frontends::Raylib`, swappable without touching the window.
- Pixel aspect and overscan ([Overscan](https://www.nesdev.org/wiki/Overscan)): "the pixel aspect ratio on a 4:3 TV
  to be 240/280*4/3 = exactly 8:7"; "Emulators and LCD HDTVs tend to use lines 8 to 231".
- Opposite directions: [Standard controller](https://www.nesdev.org/wiki/Standard_controller) says nothing about
  holding them together, so there is no documented console behaviour to emulate: a project decision (decision 3).

## Scope

In:

- Window with integer scaling (`--scale N`), aspect option (`--aspect square|8:7`), overscan crop option
  (`--crop-overscan`, lines 8 to 231).
- Keyboard mapping with defaults (arrows, Z = B, X = A, Enter = Start, Right Shift = Select) and a config file
  (`~/.config/ruby-nes/config.yml`, or `--config PATH`); opposite directions filtered here (plan 15, decision 2: the
  core does not filter them).
- Hotkeys: pause, reset, quit, toggle the frame rate overlay.
- Frame pacing with drift correction.
- Command line: `ruby-nes ROM [--scale N] [--aspect square|8:7] [--crop-overscan] [--config PATH]
  [--jit=none|yjit|zjit] [--headless …]`. Plan 16 built `Ruby::Nes::CommandLine` and `CommandLine::Options`; they are
  extended, and the window runs through `Frontends::Driver`. The pacing belongs to the windowed frontend (in
  `present`), so the driver stays the same for every frontend.

Out: audio (plan 24), save states (backlog), gamepads (backlog, decision 2).

## Decisions

Settled with the user on 2026-11-20.

1. **YJIT is the default JIT**, for the window and the headless run (decision 19 of `docs/architecture.md`; revisit
   after plan 25). `--jit=none|yjit|zjit`.
2. **Gamepads later** (backlog). `Frontends::Keyboard` is already a generic code → button map, so a gamepad can reuse
   it.
3. **Opposite directions cancel each other**: Left with Right, or Up with Down, held together reach the controller as
   neither. Stateless, always on in the window. Reason: no documented behaviour to emulate; the simplest rule.
4. **Square pixels and all 240 lines by default**; `--aspect 8:7` stretches the width by 8/7, `--crop-overscan` shows
   lines 8 to 231 only.
5. **Pause and reset go through the driver contract**: `Frontends::Base#paused?` and `#reset_requested?` (false by
   default). Before each frame the driver resets the console when asked; while paused it presents the last frame
   again without running one, so the window keeps drawing, reading keys and pacing. Reason: the frontend never holds
   the console; the headless frontend is unchanged.
6. **Default hotkeys**: Esc quits, P pauses, R resets, F shows or hides the frame rate (shown by default). The
   overlay reads `60.1 fps | yjit` (raylib's default font has no `·`; the JIT is written as `--jit` names it), the JIT
   taken from `enabled?`, not from the option; the command line prints `JIT: yjit` when it starts, headless included.
   A JIT whose `enable` returns false is an error too (decision 8).
7. **Config file**: `~/.config/ruby-nes/config.yml` (or `--config PATH`), a `keys:` section mapping an action to a key
   name or a list of key names (`a: x`, `b: [z, space]`, `pause: p`). Actions are the eight controller buttons plus
   `pause`, `reset`, `quit` and `frame_rate`. A partial config overrides the defaults action by action, and a key it
   gives to an action is taken from the default of any other (`a: z` leaves B, whose default is Z, without a key); the
   actions left without a key are named on the error output when the window opens. A missing default file means the
   defaults; a missing `--config` file is an error. An unknown action, a section other than `keys:` (a later plan adds
   its own), a value that is not a key name or a list of them (YAML's null, booleans, numbers), an unknown key name, a
   key bound to two actions or malformed YAML is an error with a message (as `InputScript`); a key repeated in one
   action counts once. Key names are raylib's `KEY_*` constants in lower case without the prefix (`right_shift`,
   `enter`; not `KEY_NULL`, "no key pressed"); the name → code table is injected (`key_codes:`), so the parser needs no
   gem.
8. **A JIT that cannot be honoured is an error**: the JIT asked is missing from this Ruby, another JIT is already on
   (through `RUBYOPT` or a flag), or `--jit=none` while one is on. Reason: the run never silently differs from what
   was asked.
9. **Options of one frontend are ignored by the other** (`--scale` headless, `--frames` in the window).
10. **The benchmark runs the window unpaced and ignores pause and reset** (`FrontendBenchmark::Unpaced`; its probe
    does not forward `paused?` and `reset_requested?`): it measures frames, not play. Its presents now include the
    overlay's `DrawText`, a small cost beside the ~3 ms of RGB conversion and upload (found by the code review).

## Tasks

- [x] `Frontends::FramePacing`: wait for the next frame's deadline (injected clock and sleep): on time, late by less
      than a frame, late by a frame or more (no catch-up burst).
- [x] `Frontends::FrameRate`: frames per second measured over one-second windows (injected clock).
- [x] `Frontends::OppositeDirections`: cancel opposite directions in a controller mask.
- [x] `Frontends::Hotkeys`: key codes to actions; quit, pause (toggle), reset (the frame it is pressed), frame rate
      overlay (toggle).
- [x] `Frontends::KeyConfig`: config loading (missing file, unknown action or key name, partial config, key lists).
- [x] `Frontends::Viewport`: window size and source rectangle from scale, aspect and crop.
- [x] `Frontends::Base` and `Frontends::Driver`: pause and reset.
- [x] `CommandLine::Jit`: enable the JIT asked, name the one running.
- [x] `CommandLine::Options`: `--jit`, `--scale`, `--aspect`, `--crop-overscan`, `--config`; `--headless` no longer
      required.
- [x] `CommandLine#run`: the window path through an injected window opener (`CommandLine::Window` by default, raylib
      loaded on demand); the JIT printed.
- [x] `Frontends::Raylib`: viewport, configurable keys, hotkeys, overlay, pacing; `bench/frontends.rb` kept working
      without pacing; smoke spec.
- [x] `docs/architecture.md` (Frontends, Layout, Decisions log), `docs/GLOSSARY.md` if a term appears, plan 24.
- [x] Manual play test.

## Acceptance criteria

- [x] An NROM game (a dump the user owns, or a freely distributable homebrew NROM game) is playable with the keyboard,
      at the speed the emulator reaches (~18 frames per second under YJIT today; real time is plan 25's).
- [x] The measured frame rate is shown; paused, the window holds 60 ± 1 without drift over 5 minutes, and the pacing
      logic is specified with a fake clock (on time, late by less than a frame, late by a frame or more).
- [x] `--jit` selects the JIT and the choice is visible (`RubyVM::YJIT.enabled?` / `RubyVM::ZJIT.enabled?`, in the
      overlay and on the output).
- [x] Keys are configurable through the file; pause, reset, quit and the overlay toggle work; opposite directions
      cancel.
- [x] 100% branch coverage on pacing, frame rate, direction filter, hotkeys, config, viewport, driver, JIT and command
      line code; rubocop clean; `bundle exec rake` green (the window smoke spec run with the display awake).

## What was done

- `Frontends::FramePacing` (deadlines a period apart at 60.0988 Hz, a period or more late restarts the schedule),
  `Frontends::FrameRate` (one-second windows), `Frontends::MonotonicClock`, `Frontends::OppositeDirections` (with the
  new `Bits.clear_flag`), `Frontends::Hotkeys`, `Frontends::KeyConfig` and `Frontends::KeyBindings` (the `keys:`
  section, names to raylib key codes; split from one unit whose spec tree outgrew the size signal),
  `Frontends::Viewport`; `paused?` and `reset_requested?` in `Frontends::Base`, acted on by `Frontends::Driver`.
- `CommandLine::Jit`, `CommandLine::ConfigFile`, `CommandLine::Window` and `CommandLine::RaylibWindow` (raylib loaded
  on demand); `CommandLine::Options` gained `--jit`, `--scale`, `--aspect`, `--crop-overscan` and `--config`, and
  `--headless` is no longer required. `Frontends::Raylib` became an adapter over those collaborators (viewport,
  configurable keys, hotkeys, `60.1 fps | yjit` overlay, injected pacing, `SetExitKey(KEY_NULL)`); the benchmark runs
  it unpaced (`FrontendBenchmark::Unpaced`).
- Manual check by the user: nestest's menu and Mario Bros. (NROM) playable from the keyboard at ~17 frames per second
  under YJIT; pause, reset, quit, overlay, `--scale`, `--aspect 8:7`, `--crop-overscan`, `--jit` and the config file
  work. Paused, 300 s in a window gave 18020 frames for 18030.5 expected, the 10 missing in the first two seconds (JIT
  warm-up) and every later second within 59-61 frames per second. With the display asleep the raylib window crashes,
  as plan 17 found.
- Independent review: a missing raylib library file is a message, not a backtrace; a key the config gives to an
  action is taken from another action's default, and actions left without a key are named; values that are not key
  names are errors, a repeated key counts once, `KEY_NULL` is not a key; a JIT whose `enable` fails is an error; the
  default config path is expanded only when read; the frame rate starts after the window opens; decisions 6, 7 and
  10 record the overlay format, the config rules and the unpaced benchmark. Not applied: the window's defaults
  (`scale: 3`, `'none'`) stay literals, since frontends do not depend on `CommandLine`; the benchmark keeps naming
  no JIT `interpreter`; `Raylib::FRAMES_PER_SECOND` (audio sizing, plan 17) is left for plan 24.

## References

- Cycle reference chart (frame rate) — https://www.nesdev.org/wiki/Cycle_reference_chart
- Overscan (pixel aspect ratio, lines 8 to 231) — https://www.nesdev.org/wiki/Overscan
- Standard controller — https://www.nesdev.org/wiki/Standard_controller
- `RubyVM::YJIT` — https://docs.ruby-lang.org/en/master/RubyVM/YJIT.html
- raylib cheatsheet (`SetExitKey`, `DrawTexturePro`, `DrawText`, `IsKeyPressed`) —
  https://www.raylib.com/cheatsheet/cheatsheet.html
