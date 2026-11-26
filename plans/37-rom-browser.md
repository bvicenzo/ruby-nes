# 37 — ROM browser

**Status:** todo

**Depends on:** 35 (state thumbnails), 36 (gamepad navigation)

## Goal

`ruby-nes` with no ROM opens a screen that lists the ROMs of a folder, shows a preview of the game in focus and starts
it. From the game, a hotkey returns to the list. Like a console's menu: no terminal needed after the first command.

## Context

- Today `ruby-nes ROM` is the only way in. `CommandLine::Options` requires exactly one ROM, and `CommandLine::Window`
  opens a window for one console and closes it at the end. A browser needs the window to outlive a game: list → game
  → list, with one window and a new console (and audio stream) per game.
- **Where a preview comes from.** An iNES file is a 16-byte header plus the program and graphics data, with no title
  and no picture. Emulators get previews in three ways:
  - artwork downloaded from a database, such as libretro-thumbnails, matched by the ROM's hash or No-Intro name;
  - their own captures: the last frame played, or a save state's thumbnail;
  - running the game: a capture of its title screen after a few seconds, or the game running live in the preview.
- What exists: the headless frontend runs a ROM without a window and writes PNGs (`--screenshot`). Plan 35 writes a
  thumbnail with each state, `states/<ROM file name>/<slot>.png` under the data directory, and starts a game on its
  most recently saved slot (`Saves::StateSlots`). raylib draws textures and text, and raylib-bindings also ships raygui.
- `docs/architecture.md` § Concurrency: single-threaded. Work in the menu (a preview being made) is sliced into the
  menu's frames, never a thread.

## Scope

In:

1. `ruby-nes` with no ROM, or with a folder, opens the browser. `ruby-nes ROM` keeps starting the game directly.
2. The list: the `.nes` files of the folder (open decision 1), each with its name from the file name and marks for a
   battery save, save states, and a mapper ruby-nes does not support (shown, with the reason, and not started).
3. Navigation from the keyboard and the gamepad (plan 36): move, start, quit. Long lists scroll.
4. The preview of the game in focus (open decision 2), cached under plan 34's data directory by the ROM's SHA-256.
5. The window's lifecycle: the window outlives each game. A hotkey in the game returns to the list (writing the
   battery save first, plan 34), and the list's quit ends the program.
6. The look (open decision 3), shared with plan 38.
7. README: the browser, the folder, the keys.

Out: artwork downloaded from the internet (backlog); folders inside folders; zipped ROMs; game names from a database.

## Open decisions

1. **Which folder.** (a) A folder given on the command line, else `roms_directory` in the config file, else `roms/`
   under the current directory. (b) Always `roms/` under the current directory. Recommendation: (a).
2. **Preview.**
   - (a) Our own captures: the last state's thumbnail (plan 35), or the frame on screen when the game was last
     closed; otherwise the title screen, made once by running the ROM headless for a few seconds, sliced into the
     menu's frames and cached. Works offline and needs no artwork.
   - (b) The game in focus runs live in the preview, in its attract mode. This is a whole emulation running inside the
     menu.
   - (c) Box art or title screens from libretro-thumbnails, downloaded and matched by hash. Needs the internet, and
     downloads copyrighted artwork. Front-ends bundled with many games (EmulationStation/ES-DE, LaunchBox) also show
     short video clips ("video snaps"), scraped from databases such as ScreenScraper or shipped in media packs: the
     same internet and copyright concerns.
   - (d) A still picture first, then the attract mode live, started from a cached save state. The emulator is
     deterministic: a game left alone from power-up always plays the same, so the "video" is the ROM itself, and a
     save state (plan 35, 10-18 KB, loaded in about 4 ms) replaces the wait until the demo starts. The first time a
     game shows up in the list, it runs headless, sliced into the menu's frames, until a few seconds past its title
     screen; that state and its frame's picture are cached by the ROM's SHA-256. Then the picture shows as soon as the
     cursor reaches the game, and once the cursor rests on it the state is loaded and the demo runs live (a console
     takes about 11 ms a frame under YJIT, within a 16.7 ms frame). To be measured with the local ROMs: how long each
     game takes to reach its demo (some have none, and show their title screen), and the cost of building a console
     at each change of focus. The preview never writes the game's battery save, and its sound is off or low.

   Recommendation: (d), a middle ground between (a) and (b) that the user liked.
3. **Look.** (a) 8-bit, drawn by us: the logo's pixel font (extended to the letters, digits and punctuation needed),
   colours of the NES palette, pixel frames and cursor. (b) raygui's widgets (lists, buttons), quicker, with a tool's
   look. Recommendation: (a), it matches the project.

## Tasks

- [ ] Options: no ROM or a folder opens the browser, TDD.
- [ ] The ROM list (scan, names, marks, unsupported mappers), TDD.
- [ ] Previews (decision 2) and their cache, TDD.
- [ ] The menu screen and its navigation, TDD.
- [ ] The window's lifecycle (list → game → list), TDD.
- [ ] README and `docs/architecture.md` (Frontends, decisions log).

## Acceptance criteria

- [ ] `bundle exec exe/ruby-nes` lists the ROMs of `roms/` with previews, starts the one picked, and the game returns
      to the list on its hotkey.
- [ ] The browser works from the gamepad alone.
- [ ] A ROM with an unsupported mapper is listed with the reason and does not start.
- [ ] `ruby-nes ROM` still starts the game directly; `rake bench:frames` keeps its digests.
- [ ] `bundle exec rake` green, branch coverage of each new unit, rubocop clean.

## References

- iNES header (what a ROM file carries) — https://www.nesdev.org/wiki/INES
- raylib cheatsheet (textures, text) — https://www.raylib.com/cheatsheet/cheatsheet.html
- libretro-thumbnails (option (c), not planned) — https://github.com/libretro-thumbnails/libretro-thumbnails
- Plans 16 (headless, PNG), 18 (window), 34 (data directory), 35 (thumbnails), 36 (gamepad)
