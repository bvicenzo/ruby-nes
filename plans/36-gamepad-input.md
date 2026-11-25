# 36 — Gamepad input

**Status:** done (2026-11-25)

**Depends on:** 18 (the window, key config and hotkeys)

## Goal

Play with a USB gamepad instead of the keyboard, starting with the user's USB SNES-style controller. A second gamepad
drives the second controller port, so two people can play.

## Context

- The window reads the keyboard only. `Frontends::Keyboard` turns key codes into the first controller's buttons,
  `Frontends::OppositeDirections` cancels left+right and up+down, and `Frontends::Raylib#button_states` returns
  `[keyboard, 0]`: the second port is always empty. `Frontends::Driver` already hands both masks to the console's
  two controllers.
- raylib reads gamepads (cheatsheet: `IsGamepadAvailable`, `GetGamepadName`, `IsGamepadButtonDown`,
  `GetGamepadAxisMovement`, `SetGamepadMappings`), and raylib-bindings 0.8.4 binds them all, with the `GAMEPAD_BUTTON_*`
  constants. raylib names buttons by position on a standard pad: `right_face_down`, `right_face_right`, `left_face_up`
  (the D-pad), `middle_left`/`middle_right` (select/start).
- A gamepad is "available" when raylib knows its layout, from the SDL GameControllerDB mappings its GLFW backend ships.
  Cheap USB pads are often generic HID devices: one may be missing from the database, or report its D-pad as axes
  instead of buttons. `SetGamepadMappings` takes a mapping line in the database's format.
- The SNES pad has four face buttons (A right, B bottom, Y left, X top), L and R, select, start and a D-pad. The NES
  pad has B and A side by side, then select, start and a D-pad.

## Findings (the user's pad, probed 2026-11-24, outside the repository)

- macOS sees it as "USB Gamepad", vendor `0x0079`, product `0x0011`, version 1.06: a generic DragonRise chip, which
  many different pads share.
- raylib (raylib-bindings 0.8.4, macOS) makes it gamepad 0, named `"USB Gamepad "` (with a trailing space), with 6 axes,
  all at 0.00 at rest. Its library carries GameControllerDB mappings for that vendor and product:
  - `03000000790000001100000006010000,Retrolink SNES Controller,a:b2,b:b1,back:b8,dpdown:+a4,dpleft:-a3,dpright:+a3,dpup:-a4,leftshoulder:b4,rightshoulder:b5,start:b9,x:b3,y:b0,platform:Mac OS X`
    matches it, with the version in its GUID (`0601`).
  - `03000000790000001100000000000000,Retrolink Classic Controller,...` is a sibling with another layout.
- With that mapping, each physical button reaches raylib as the standard button of its position. The D-pad's axes
  become buttons, and no axis moves past 0.5:

  | Pad | raylib (`GAMEPAD_BUTTON_*`) |
  |---|---|
  | D-pad up, down, left, right | `LEFT_FACE_UP`, `LEFT_FACE_DOWN`, `LEFT_FACE_LEFT`, `LEFT_FACE_RIGHT` |
  | A, B, X, Y | `RIGHT_FACE_RIGHT`, `RIGHT_FACE_DOWN`, `RIGHT_FACE_UP`, `RIGHT_FACE_LEFT` |
  | L, R | `LEFT_TRIGGER_1`, `RIGHT_TRIGGER_1` |
  | Select, Start | `MIDDLE_LEFT`, `MIDDLE_RIGHT` |

- So this pad needs no mapping line of ours: defaults written in raylib's standard names fit it as it is. The mapping
  line (scope item 5) is for pads that share the chip and not the layout, which may get the Classic Controller's
  mapping or none.
- On Linux (probed 2026-11-25, the machine the plan is built on): the kernel reports `Bus=0003 Vendor=0079
  Product=0011 Version=0110`, named `"USB Gamepad "`, with two axes (the D-pad) and a read ACL for the logged-in user
  (uaccess), so no `input` group is needed. Version 0110 matches the Linux line of raylib's library,
  `03000000790000001100000010010000,Retrolink SNES Controller,a:b2,b:b1,back:b8,dpdown:+a1,dpleft:-a0,dpright:+a0,dpup:-a1,leftshoulder:b4,rightshoulder:b5,start:b9,x:b3,y:b0,platform:Linux,`:
  the same layout as on macOS. raylib, in a hidden window, makes it gamepad 0, every axis at 0.0 at rest.
- Inside the window on Linux (2026-11-25, each button pressed): the D-pad reaches raylib as `LEFT_FACE_UP`, `_DOWN`,
  `_LEFT`, `_RIGHT`, the four face buttons as the four `RIGHT_FACE_*`, Start as `MIDDLE_RIGHT`; no axis moved past 0.2
  while the D-pad was held, so the D-pad never doubles as the stick.
- The probe also showed what a mismatched mapping looks like: buttons that answer as other buttons, and select/start
  that light several directions at once. The README's troubleshooting can describe it.

## Scope

In:

1. Step 1, the probe of the user's pad: done, see Findings. When the plan starts, it is repeated inside the window with
   each button pressed, to confirm the table on Linux and that the D-pad never also reports as an axis. The findings
   go into the README.
2. `Frontends::Keyboard` holds nothing of a keyboard (an input code to a button, `buttons { |code| held? }`): renamed
   `Frontends::Controls`, it serves the keys and the gamepad buttons alike.
3. A gamepad unit: its buttons through `Controls`, and the left stick past a dead zone as directions, to a controller
   mask. A players unit combines the inputs into both ports (decision 2); opposite directions are cancelled per port.
4. A `gamepad:` section in the config file, with the key config's rules (each action takes a button name or a list,
   `[]` for none, the file wins, a button drives one action), and its defaults (decision 1). Button names are raylib's
   `GAMEPAD_BUTTON_*` constants, lower case without the prefix, as key names are.
5. Plugging in or pulling out a gamepad while the game runs: asked once per frame, it never stops the game.
6. An optional `gamepad_mappings:` text in the config, for a pad missing from raylib's database, passed to
   `SetGamepadMappings` once the window is open.
7. README: the gamepad section, the defaults, the config, what to do with a pad raylib does not know.

Out: rumble; analog sensitivity beyond a dead zone; remapping on screen (plan 38); hotkeys on the pad (plan 38,
decision 3); keys for controller 2 on the keyboard.

## Decisions

1. **The default layout goes by letter.** SNES A (right) is NES A and SNES B (bottom) is NES B; X (top) repeats A and
   Y (left) repeats B: `a: [right_face_right, right_face_up]`, `b: [right_face_down, right_face_left]`,
   `select: middle_left`, `start: middle_right`, the directions `left_face_*`. L and R do nothing. The letters match
   and a person reaches for them; it stays configurable.
2. **Players are fixed, with no config:** port 1 is the keyboard and the first gamepad (raylib's gamepad 0), their
   buttons combined; port 2 is the second gamepad (gamepad 1). One person with one pad plays as player 1, the keyboard
   still at hand. An override per pad is YAGNI until someone needs it.
3. **Hotkeys on the pad belong to plan 38**, with the combination that opens its pause menu. Here `gamepad:` takes
   controller buttons only; a hotkey under it is a config error. `Frontends::Hotkeys` keeps a single input source.
4. **`gamepad_mappings:` is optional text in the SDL GameControllerDB format**, one mapping per line, passed to
   `SetGamepadMappings` after the window opens (GLFW must be initialised). Refined while building: the plan said a
   refused text would stop the run, but raylib 5.5 (raylib-bindings 0.8.4) returns 1 for any text, garbage and empty
   included, as GLFW skips the lines it cannot read without reporting them (run 2026-11-25), so the text is passed
   unchecked and the README says to test the pad after adding a line. Actions left without a gamepad button are not
   warned about: a person without a pad would always see the warning. The warning for keys stays.
5. **The left stick drives the directions too**, past a dead zone of 0.5 on each axis (raylib's axes go from -1 to 1,
   up is negative), for pads with analog sticks. On the SNES pad its axes stay at 0, the mapping turns them into D-pad
   buttons.
6. **A gamepad's presence is asked every frame** (`IsGamepadAvailable`); an absent one holds nothing. raylib follows
   plugging in and out itself, so pulling the pad out releases its buttons and plugging it back in resumes.

7. **(Review) Ports follow raylib's pad numbers.** With two pads in, pulling out the first leaves the second as player
   2: renumbering on the fly would hand player 1's controller to player 2 mid-game. The README says so.

## Tasks

- [x] Step 1: probe the user's pad, record the findings (2026-11-24; confirm inside the window when the plan starts).
- [x] Confirm the probe inside the window, each button pressed (Linux).
- [x] `Frontends::Keyboard` renamed `Frontends::Controls`.
- [x] `Frontends::KeyBindings` names gamepad buttons too (`codes:`, the kind of input in its errors), TDD.
- [x] `Frontends::KeyConfig`: a section collaborator; `gamepad:` and `gamepad_mappings:`, TDD.
- [x] `Frontends::Gamepad` (buttons, left stick) and `Frontends::StickDirections` (dead zone), TDD.
- [x] `Frontends::Players` (both ports, absent pads, opposite directions), TDD.
- [x] `Frontends::RaylibInput` and `Frontends::Raylib` (gamepad button codes, mappings, button states), TDD.
- [x] `CommandLine::Window` and `CommandLine::RaylibWindow` pass the gamepad config, TDD.
- [x] README (Playing: gamepads), `docs/architecture.md` (Frontends, Layout, decisions log), plan 38 and the backlog.

## Acceptance criteria

- [x] Super Mario Bros. 3 plays from the user's SNES pad, D-pad and buttons, with no keyboard (manual test,
      2026-11-25).
- [x] A second pad plays as player 2 (Mario Bros. has two players): specified (`Frontends::Players`), not tried by
      hand, as only one pad was at hand.
- [x] Pulling the pad out and plugging it back in while playing works without restarting (manual test, 2026-11-25).
- [x] The keyboard keeps working as before (manual test, 2026-11-25).
- [x] `bundle exec rake` green, branch coverage of each new unit, rubocop clean. One failure on the Linux machine it
      ran on, not of this plan: `raylib_picture_spec.rb:33` (a shader that should not link links under that GPU
      driver) fails on the base commit too.

## What was done

- **One mapping for keys and pad buttons:** `Frontends::Keyboard` became `Frontends::Controls` (an input code to a
  button); `Frontends::KeyBindings` takes the codes and the kind of input it names (`codes:`, `kind:`), so the same
  pair serves the keyboard (`KEY_CODES`) and the pads (`GAMEPAD_BUTTON_CODES`).
- **Config:** `Frontends::KeyConfig::Section` holds one section's rules (a name or a list, `[]` for none, the file
  wins, unknown actions listed with the ones it takes); `KeyConfig` reads `keys:`, `gamepad:` (defaults by letter,
  decision 1) and the optional `gamepad_mappings:` text, handed to `SetGamepadMappings` once the window is open.
- **Pads to ports:** `Frontends::StickDirections` (the left stick past a 0.5 dead zone), `Frontends::Gamepad` (its
  buttons and stick) and `Frontends::Players` (port 1 the keyboard and gamepad 0 combined, port 2 gamepad 1, an
  absent pad holds nothing, opposite directions cancelled per port), reading from `Frontends::RaylibInput`, a thin
  adapter over raylib's input functions. `CommandLine::Window` passes the gamepad config to the window.
- **Probe:** the pad's buttons, pressed one by one inside the window on Linux, reach raylib as the Findings' table,
  and the D-pad never moves an axis.
- **Manual test:** Super Mario Bros. 3 played from the SNES pad alone, survived the pad pulled out and plugged back in
  mid-level, and the keyboard kept working. Player 2 on a second pad is specified only.
- **Review:** applied a public `StickDirections.direction` for the dead-zone boundaries, a `.new` spec of the mappings
  handed to raylib, sections taking their actions from their defaults and naming their kind of input, unknown actions
  listed with the ones a section takes, `RaylibCanvas` in the input smoke test, named binary masks in specs, `gamepad`
  instead of `index`, comment and glossary fixes, and decision 7 (ports follow raylib's pad numbers). Declined one
  finding.

## References

- Standard controller (buttons, report order) — https://www.nesdev.org/wiki/Standard_controller
- raylib cheatsheet (gamepad functions) — https://www.raylib.com/cheatsheet/cheatsheet.html
- SDL GameControllerDB (mapping format) — https://github.com/mdqinc/SDL_GameControllerDB
- raylib's gamepad API (`GAMEPAD_BUTTON_*`, axes, `SetGamepadMappings`) — https://github.com/raysan5/raylib/blob/master/src/raylib.h
- Plan 15 (controllers), plan 18 (key config, decision 7)
