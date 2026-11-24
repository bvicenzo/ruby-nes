# 36 — Gamepad input

**Status:** todo

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
- The probe also showed what a mismatched mapping looks like: buttons that answer as other buttons, and select/start
  that light several directions at once. The README's troubleshooting can describe it.

## Scope

In:

1. Step 1, the probe of the user's pad: done, see Findings. When the plan starts, it is repeated inside the window to
   confirm the D-pad never also reports as an axis (which would need the dead zone of item 2 not to double it). The
   findings go into the README.
2. A gamepad unit, like `Frontends::Keyboard`: raylib gamepad buttons, and axes past a dead zone as directions, to a
   controller mask. Opposite directions are cancelled as they are for the keyboard.
3. Defaults for a standard pad (open decision 1), and a `gamepad:` section in the config file, with the key config's
   rules (each action takes a button name or a list, `[]` for none, the file wins). Hotkeys can be bound to buttons
   too (open decision 3).
4. Players (open decision 2), and plugging in or pulling out a gamepad while the game runs: checked once per frame, it
   never stops the game.
5. An optional mapping line or file for a pad missing from raylib's database, passed to `SetGamepadMappings`.
6. README: the gamepad section, the defaults, the config, what to do with a pad raylib does not know.

Out: rumble; analog sensitivity beyond a dead zone; remapping on screen (plan 38).

## Open decisions

1. **Default layout on a SNES pad.**
   - (a) By letter: SNES A (right) is NES A, SNES B (bottom) is NES B. Y and X repeat B and A.
   - (b) By position: SNES Y and B (the left pair) are NES B and A, matching the NES pad's B-left, A-right.

   Recommendation: (a), the letters match and a person reaches for them. On the user's pad (Findings) that is
   `right_face_right` for A and `right_face_down` for B. Either way it stays configurable.
2. **Players.** (a) The keyboard and the first gamepad both drive port 1 (their buttons combined), and the second
   gamepad drives port 2. (b) Each gamepad is assigned a port in the config. Recommendation: (a), with (b) as a config
   override.
3. **Hotkeys on the pad.** (a) A combination such as select+start opens plan 38's pause menu, once it exists; until
   then no hotkey is bound to the pad by default. (b) None. Recommendation: (a), so a person on the couch never needs
   the keyboard.

## Tasks

- [x] Step 1: probe the user's pad, record the findings (2026-11-24; confirm inside the window when the plan starts).
- [ ] The gamepad unit (buttons, axes, dead zone), TDD.
- [ ] The config's `gamepad:` section and its defaults, TDD.
- [ ] The window: polling, players, plugging in and out, mappings, TDD.
- [ ] README (Playing: gamepads) and `docs/architecture.md` (Frontends, decisions log).

## Acceptance criteria

- [ ] Super Mario Bros. 3 plays from the user's SNES pad, D-pad and buttons, with no keyboard.
- [ ] A second pad plays as player 2 (Mario Bros. has two players).
- [ ] Pulling the pad out and plugging it back in while playing works without restarting.
- [ ] The keyboard keeps working as before.
- [ ] `bundle exec rake` green, branch coverage of each new unit, rubocop clean.

## References

- Standard controller (buttons, report order) — https://www.nesdev.org/wiki/Standard_controller
- raylib cheatsheet (gamepad functions) — https://www.raylib.com/cheatsheet/cheatsheet.html
- SDL GameControllerDB (mapping format) — https://github.com/mdqinc/SDL_GameControllerDB
- Plan 15 (controllers), plan 18 (key config, decision 7)
