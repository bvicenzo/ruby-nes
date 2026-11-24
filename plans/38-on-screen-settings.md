# 38 — On-screen settings and pause menu

**Status:** todo

**Depends on:** 36 (gamepad bindings), 37 (the menu's look and the window's lifecycle)

## Goal

Change the keyboard and gamepad controls inside the window, without editing YAML: pick an action, press the key or
button for it, done. In the game, a pause menu gathers what today is a hotkey list: resume, save and load states,
controls, reset, back to the list, quit.

## Context

- Controls live in `~/.config/ruby-nes/config.yml` (`keys:` since plan 18, `gamepad:` from plan 36), read once by
  `Frontends::KeyConfig`. Its rules: an action takes a list of keys, `[]` leaves it without one, and a key the file
  gives to another action leaves its default action.
- Writing that file back from the program is new. Today it is only read, and people may have written comments in it.
- Plan 37 brings the menu's look and a window that outlives a game. Plan 35 brings save state slots. Plan 36 brings
  gamepad bindings and, open decision 3 there, a pad combination meant to open this menu.

## Scope

In:

1. A controls screen, reachable from the ROM list and from the pause menu: every controller button and hotkey with
   its keys and gamepad buttons. Choose one, then press the new key or button (Escape, or a timeout, cancels). A key
   already bound elsewhere moves to the new action, as the config file's rule does, and the screen says so.
2. Saving writes the config file (open decision 1), and the running game uses the new bindings at once.
3. Restoring the defaults, for one action or for all.
4. A pause menu over the paused game: resume, save state, load state (with the slots and their thumbnails), controls,
   reset, back to the ROM list, quit. It opens from the keyboard and from the gamepad (plan 36, decision 3).
5. README: the menus, and the config file's sections as written by the program.

Out: video and audio settings on screen (scale, aspect, overscan, volume), which could be a later plan.

## Open decisions

1. **Writing the config file.** (a) Write the whole `keys:`/`gamepad:` sections, warning in the README that comments
   in the file are lost. (b) Edit only the lines that changed, keeping comments, which needs a YAML round-trip the
   standard library does not offer. (c) Write the settings to a second file of the program's own that overrides the
   hand-written one. Recommendation: (a), with a backup of the previous file (`config.yml.bak`).
2. **Pause menu vs the pause hotkey.** (a) The pause hotkey (P) keeps pausing silently, and a new key (Escape) opens
   the menu, quitting moves into the menu. (b) P opens the menu. Recommendation: (a); Escape quitting at once today is
   the riskier key to keep.

## Tasks

- [ ] The binding editor (choose, capture, move, cancel, defaults), TDD.
- [ ] Writing the config file (decision 1), TDD.
- [ ] The controls screen, TDD.
- [ ] The pause menu and its actions, TDD.
- [ ] README and `docs/architecture.md` (Frontends, decisions log).

## Acceptance criteria

- [ ] A key and a gamepad button are rebound on screen, work at once, and are still bound after reopening the
      program.
- [ ] A key taken from another action leaves that action, and the screen shows it.
- [ ] The pause menu saves and loads a state, resets, returns to the list and quits, from the keyboard and from the
      gamepad.
- [ ] `bundle exec rake` green, branch coverage of each new unit, rubocop clean.

## References

- Plan 18 (key config, decision 7), plans 35, 36 and 37
- raylib cheatsheet (key and gamepad input) — https://www.raylib.com/cheatsheet/cheatsheet.html
