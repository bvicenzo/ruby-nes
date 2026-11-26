# 40 — On-screen controls

**Status:** todo

**Depends on:** 38 (the pause menu, its screens and the list's menu)

## Goal

Change the keyboard and gamepad controls inside the window, without editing YAML: pick an action, press the key or
button for it, done. Split off from plan 38 (its decision 1), which built the menus this screen is reached from.

## Context

- Controls live in `~/.config/ruby-nes/config.yml` (`keys:` since plan 18, `gamepad:` since plan 36), read once by
  `Frontends::KeyConfig`. Its rules (`KeyConfig::Section`): an action takes a list of inputs, `[]` leaves it without
  one, and an input the file gives to another action leaves its default action. `Frontends::KeyBindings` refuses an
  input bound to two actions.
- Writing that file back from the program is new. Today it is only read, and people may have written comments in it.
- Plan 38 brings `Frontends::Screens` (the pixel font, `Canvas`, `Choices`, `ButtonPresses`), the pause menu
  (`CommandLine::Pause`) and the list's menu; this plan adds a CONTROLS entry to both. Plan 38 also made Escape the
  `menu` hotkey and L + R on gamepad 0 the pad's fixed way into the menus (plan 38, decisions 2 and 3).
- Plan 36 left hotkeys on the pad to plan 38, which passed them here (plan 38, decision 1): `gamepad:` binds
  controller buttons only, and `Frontends::Hotkeys` reads the keyboard only.
- The window builds its `Frontends::Players` and `Frontends::Hotkeys` from the config when it opens
  (`Frontends::Raylib#initialize`); new bindings need to reach them while it runs.

## Scope

In:

1. A controls screen, reachable from the list's menu and from the pause menu: every controller button and hotkey with
   its keys and gamepad buttons. Choose one, then press the new key or button (the menu's keys, or a timeout, cancel).
   An input already bound elsewhere moves to the new action, as the config file's rule does, and the screen says so.
2. Saving writes the config file (open decision 1), and the running game uses the new bindings at once.
3. Restoring the defaults, for one action or for all.
4. Hotkeys on the pad: `gamepad:` takes hotkeys too (open decision 3), and the controls screen edits them.
5. README: the controls screen, and the config file's sections as written by the program.

Out: video and audio settings on screen (scale, aspect, overscan, volume), which could be a later plan.

## Open decisions

1. **Writing the config file.** (a) Write the whole `keys:`/`gamepad:` sections, warning in the README that comments
   in the file are lost. (b) Edit only the lines that changed, keeping comments, which needs a YAML round-trip the
   standard library does not offer. (c) Write the settings to a second file of the program's own that overrides the
   hand-written one. Recommendation: (a), with a backup of the previous file (`config.yml.bak`), writing only the
   actions that differ from their defaults (the file's rule reads them back the same), atomically
   (`Saves::AtomicFile`), to the file `--config` names or the default one.
2. **A new input replaces or joins the action's.** (a) Replaces them: one input per action from the screen, lists
   still possible in the file. (b) Joins them, with a way to clear an action. Recommendation: (a), as console
   emulators do; restoring the defaults brings lists back.
3. **Hotkeys on the pad.** (a) `gamepad:` takes hotkeys, none bound by default; `Frontends::Hotkeys` reads gamepad 0
   too. (b) Hotkeys stay on the keyboard. Recommendation: (a), so L or R alone can save and load a state.
4. **Capturing an input.** Keys through raylib's key queue (`GetKeyPressed`), pad buttons by asking each of
   `GAMEPAD_BUTTON_CODES` whether it was pressed on gamepad 0; the `menu` action's keys and L + R are never captured,
   they cancel. To be confirmed by a probe in the window.

## Tasks

- [ ] The binding editor (choose, capture, move, cancel, defaults), TDD.
- [ ] Writing the config file (decision 1), TDD.
- [ ] Rebinding the running window (`Players`, `Hotkeys`), TDD.
- [ ] Hotkeys on the pad (decision 3), TDD.
- [ ] The controls screen, and its entry in the pause menu and the list's menu, TDD.
- [ ] README and `docs/architecture.md` (Frontends, decisions log).

## Acceptance criteria

- [ ] A key and a gamepad button are rebound on screen, work at once, and are still bound after reopening the
      program.
- [ ] An input taken from another action leaves that action, and the screen shows it.
- [ ] The defaults come back for one action and for all.
- [ ] `bundle exec rake` green, branch coverage of each new unit, rubocop clean.

## References

- Plan 18 (key config, decision 7), plans 36, 37 and 38
- raylib cheatsheet (key and gamepad input) — https://www.raylib.com/cheatsheet/cheatsheet.html
