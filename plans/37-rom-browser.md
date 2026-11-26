# 37 — ROM browser

**Status:** done (2026-11-26)

**Depends on:** 35 (save states), 36 (gamepad navigation)

## Goal

`ruby-nes` with no ROM opens a screen that lists the ROMs of a folder, shows a preview of the game in focus and starts
it. From the game, a hotkey returns to the list. Like a console's menu: no terminal needed after the first command.

## Context

- Today `ruby-nes ROM` is the only way in. `CommandLine::Options` requires exactly one ROM, and `CommandLine::Window`
  opens a window for one console and closes it at the end. A browser needs the window to outlive a game: list → game
  → list, with one window and a new console per game.
- **Where a preview comes from.** An iNES file is a 16-byte header plus the program and graphics data, with no title
  and no picture. Emulators get previews in three ways:
  - artwork downloaded from a database, such as libretro-thumbnails, matched by the ROM's hash or No-Intro name;
  - their own captures: the last frame played, or a save state's thumbnail;
  - running the game: a capture of its title screen after a few seconds, or the game running live in the preview.
- What exists: the headless frontend runs a ROM without a window. Plan 35 restores a console from a save state in
  about 4 ms (`Saves::ConsoleState`), and the state holds the PPU's frame buffer, so a restored state is also a
  picture. `Frontends::RaylibPicture` draws any 256×240 frame buffer of palette indices.
- `docs/architecture.md` § Concurrency: single-threaded. Work in the menu (a preview being made) is sliced into the
  menu's frames, never a thread.
- **Measured (2026-11-25, YJIT, the six local ROMs left alone from power-up, distinct frames per second and a contact
  sheet):** the picture starts moving after 2 s in Bomberman II (opening scene), Zelda (the title's waterfall) and
  Super Mario Bros. 3 (the curtain and opening); after 14 s in Castlevania and 15 s in Mario Bros. (a still title, then
  the demo); after 22 s in Super Pitfall (a still title, then a short demo). Building a console takes 1-3 ms; a
  restored console runs a frame in 9-14 ms, as one that never stopped; composing a menu frame in Ruby (background,
  half-size preview, 15 rows of text) takes 0.56 ms.

## Scope

In:

1. `ruby-nes` with no ROM, or with a folder, opens the browser. `ruby-nes ROM` keeps starting the game directly.
2. The list: the `.nes` files of the folder (decision 1), each with its name (decision 4) and marks for a battery save,
   save states, and a ROM ruby-nes cannot run (an image that is not iNES, an unsupported mapper: shown, with the
   reason, and not started).
3. Navigation from the keyboard and the gamepad (decision 6): move, page, start. Long lists scroll.
4. The preview of the game in focus (decision 2), cached under plan 34's data directory by the ROM's SHA-256.
5. The window's lifecycle: the window outlives each game. Escape in the game returns to the list (writing the battery
   save first, plan 34), and Escape in the list ends the program (decision 5).
6. The look (decision 3), shared with plan 38.
7. README: the browser, the folder, the keys.

Out: artwork downloaded from the internet (backlog); folders inside folders; zipped ROMs; game names from a database;
returning to the list and quitting from the gamepad (plan 38's pad combination, plan 36 decision 3).

## Decisions

1. **The folder:** the one given on the command line, else `roms_directory:` in the config file (`~` expanded), else
   `roms/` under the current directory. A folder that does not exist is an error, as a missing ROM is; an empty one
   shows "NO ROMS IN <folder>". The command line wins, the config saves typing it.
2. **Preview: a cached save state of the attract mode, made when the game is first in focus** (option (d) of the
   discussion). The emulator is deterministic: a game left alone from power-up always plays the same, so the "video"
   is the ROM itself.
   - Once the cursor has rested on a game for about half a second (30 frames), it runs live, one frame per menu frame.
   - With no cached state, it runs from power-up, and the menu watches it (`Browser::MotionWatch`): the first second
     (60 frames) that shows at least 30 different pictures marks the moving picture, and the console's state is written
     there to `previews/<ROM SHA-256>.state` under the data directory, atomically. With no motion within 60 seconds,
     the state is written then. Refined while building: counting the frames that differ from the one before found
     Super Pitfall moving in its first second, as its title cycles through a few pictures, 20 s before its demo;
     counting different pictures (a frame buffer's hash, about 0.4 ms) finds the six local games moving at 3, 14, 2,
     16, 2 and 22 s (Bomberman II, Castlevania, Zelda, Mario Bros., Super Mario Bros. 3, Super Pitfall), as the
     contact sheet shows.
   - With a cached state, the state is restored as soon as the cursor reaches the game: its frame buffer is the still
     picture, shown at once, and once the cursor rests the demo goes on from there. No PNG is kept.
   - A cached state ruby-nes refuses (another version of the code) or finds damaged is dropped and made again from
     power-up.
   - The preview's console has no sound and never loads or writes the battery save; nothing runs in the background.
   Why: the user liked a middle ground between our own still captures and a live attract mode; the measurements show
   most demos start within 15 s and the cache skips the wait the next time. A background scan of every ROM was
   declined as more code and a busy CPU in the menu.
3. **Look: an NES frame drawn by us.** The menu is composed as a 256×240 frame buffer of palette indices and drawn by
   the window's `Frontends::RaylibPicture`, like a game: colours of the NES palette by construction, no new drawing
   code in the window, and specs that check pixels without raylib. The preview at half size (128×120) at the top, in a
   frame; the list below, with the cursor, scrolling and the marks; the reason in the preview's place for a ROM that
   cannot run. Everything stays within lines 8-231, so `--crop-overscan` hides none of it
   (https://www.nesdev.org/wiki/Overscan). raygui's widgets were declined: a tool's look.
4. **Font and names:** an 8×8 pixel font of our own, upper case, digits, punctuation and the marks' icons, written as
   a readable table in the code (the logo's font only has the letters of "ruby-nes"). A name is the file's, without
   its No-Intro tags (`(...)`, `[...]`), in upper case: "LEGEND OF ZELDA, THE"; the tags show under the preview of the
   game in focus. The list is sorted by name.
5. **Escape goes up one level:** in a game started from the list it returns to the list, writing the battery save
   first; in the list it ends the program; the window's close button always ends it. `ruby-nes ROM` keeps Escape
   quitting. Plan 38 turns Escape in the game into its pause menu, which has "back to the list".
6. **Navigation reads controller 1's buttons** (`Frontends::Players`: the keyboard and gamepad 0 combined), as an NES
   game's menu does: up and down move, repeating while held; left and right turn a page; A or Start starts the game.
   No new input binding is needed.
7. **One window and one audio stream for the whole session;** each game gets a new console. The menu queues a frame of
   silence each frame, so the audio keeps pacing it; between screens the audio queued is dropped and the hotkeys start
   over (not paused, not quitting).

## Tasks

- [x] `Saves::ConsoleState#rom_digest` public, TDD.
- [x] Options: no path or a folder opens the browser; `--headless` needs a ROM, TDD.
- [x] `roms_directory:` in the config file (`Frontends::KeyConfig`), TDD.
- [x] The ROM list: names (`Browser::RomName`, `Browser::PixelFont.printable`), scan, marks, reasons
      (`Browser::RomList`, `Browser::Rom`), TDD.
- [x] Navigation: `Browser::ButtonPresses` (presses and repeat), `Browser::Cursor` (focus, page, scroll), TDD.
- [x] Previews: `Browser::MotionWatch`, `Saves::Directory#preview_path`, `Browser::PreviewCache`, `Browser::Preview`,
      TDD.
- [x] The screen: `Browser::PixelFont`, `Browser::Screen`, `Browser::Menu`, `Browser::EmptyMenu`, TDD.
- [x] The window's lifecycle: `Frontends::Base#closed?`/`#next_screen` (raylib, `Hotkeys#restart`),
      `CommandLine::Game` (out of `CommandLine::Window`), `CommandLine::Window#browse`, `CommandLine::Browser`,
      `CommandLine#run`, TDD.
- [x] README and `docs/architecture.md` (Frontends, Layout, decisions log), `docs/GLOSSARY.md`; plan 38.

Refined while building:

- **Hidden files are left out of the list.** The local `roms/` holds macOS's `._<ROM>.nes` files (AppleDouble), named
  like the ROMs; they were listed as "NOT AN INES IMAGE".
- **The list has 10 rows (19-28),** a blank row between the focus's tags and the list.
- **The window's two entry points share the config, the window and its closing:** `CommandLine::Window#run` plays a
  ROM, `#browse` picks and lists the folder before the window opens (a folder that cannot be read opens no window) and
  hands the open window to `CommandLine::Browser`'s loop. A game in an open window is `CommandLine::Game` (`load`,
  `play`, `close`), out of `Window`.
- **The list is read again when a game ends,** so its marks are fresh, the focus on the game played (`Menu`'s `focus:`),
  and one `ButtonPresses` outlives the menus, so a button held as a game ends is no new press.
- **A game that cannot be started, or whose save cannot be written as it closes, is a message in the window** (the
  window's notice, plan 35) and a warning, and the list comes back.
- **From the independent review:**
  - only the directions repeat, so A or Start held as a game ends no longer starts it again;
  - the focus's tags are cut to a row;
  - a ROM that cannot run is listed in grey (its mark), and an unreadable file is a ROM that "CANNOT BE READ";
  - the preview's frame moved down a line, so nothing is drawn on line 7, which `--crop-overscan` hides;
  - the preview gives the reason a cartridge with a good header cannot be loaded, shown in its place;
  - the menu asks the window for silence (`Frontends::Base#queue_silence`) only when it is not paused;
  - a folder with no ROM is `Browser::EmptyMenu`;
  - a `~user` with no home in `roms_directory:` is a config error.
- **Measured with the browser running headless over `roms/` (YJIT):** 11-12 ms a menu frame with the preview running
  live, and Castlevania's preview cached at its demo within 1000 frames.

## Acceptance criteria

- [x] `bundle exec exe/ruby-nes` lists the ROMs of `roms/` with previews, starts the one picked, and Escape in the
      game returns to the list with the battery save written (manual test).
- [x] The list is navigated and a game started from the gamepad alone (returning and quitting from the pad: plan 38)
      (manual test).
- [x] A ROM with an unsupported mapper is listed with the reason and does not start (`RomList`, `Menu`, `Screen`
      specs).
- [x] The second time the cursor rests on a game, its picture shows at once and the demo goes on from the cached
      state (`Preview` spec; manual test).
- [x] `ruby-nes ROM` still starts the game directly and Escape quits it (`CommandLine` and `Window` specs; Escape is
      the hotkeys' quit, unchanged); `rake bench:frames` keeps its digests (f0903fbc59bf / 10369a5b40df, 2026-11-25).
- [x] `bundle exec rake` green (3116 examples), branch coverage of each new unit, rubocop clean.

## What was done

- `ruby-nes` with no path, or with a folder, opens the ROM browser on the command line's folder, else the config's
  `roms_directory:`, else `roms/` (`CommandLine::Options`, `Frontends::KeyConfig`, `CommandLine::Window#browse`).
- `Frontends::Browser` composes the menu as a 256x240 NES frame of palette indices drawn by the existing picture:
  `PixelFont` (8x8 upper-case glyphs and the marks), `RomName` and `RomList` (names without No-Intro tags, the reason
  a ROM cannot run, the battery save and save state marks), `Cursor`, `ButtonPresses` (only directions repeat),
  `Screen`, `Menu` and `EmptyMenu`. Everything stays on lines 8-231.
- `Preview` gives the game in focus a silent console: a cached state (`PreviewCache`,
  `previews/<ROM SHA-256>.state`) shows at once, the console runs live after 30 frames of rest, and `MotionWatch`
  caches the state once a second has 30 distinct pictures (or after 3600 frames); a refused state is made again.
- `CommandLine::Game` was extracted from `Window` (load, play, close), and `CommandLine::Browser` loops between the
  menu and the games in one window; `Frontends::Base` gained `closed?`, `next_screen` and `queue_silence`, and
  `Hotkeys#restart` resets quit and pause between screens. Escape in a game started from the list returns to it.
- Checked by hand on the six local games: previews, the gamepad, the cached picture on the second rest, and returning
  from a game with its battery save written.

## How to test

1. `bundle exec exe/ruby-nes`: the list of the games in `roms/` opens.
2. Rest on Castlevania: after half a second the title runs live, and the demo starts at about 14 s.
3. Move away and back to Castlevania: the picture shows at once, and the demo goes on without the title's wait.
4. Up, down, left and right on the keyboard and on the pad: the list scrolls and repeats while held.
5. Start Zelda with A or Start on the pad, play, press Escape: back to the list, and its `.sav` is written.
6. Escape in the list quits. `bundle exec exe/ruby-nes roms/smb3.nes` starts the game directly, and Escape quits.

## Glossary

- **Attract mode (demo):** a game playing itself from its title screen, left alone.
- **No-Intro tags:** the parts of a ROM's file name in brackets, such as `(USA)` and `(Rev 1)`.
- **Overscan:** the edges an old TV cut off; `--crop-overscan` shows lines 8-231 only.

## References

- iNES header (what a ROM file carries) — https://www.nesdev.org/wiki/INES
- Overscan (lines 8-231) — https://www.nesdev.org/wiki/Overscan
- PPU registers, PPU power up state, PPU palettes (the specs' backdrop program: the address latch, writes ignored until
  the first VBlank ends, the backdrop drawn with rendering off) — https://www.nesdev.org/wiki/PPU_registers,
  https://www.nesdev.org/wiki/PPU_power_up_state, https://www.nesdev.org/wiki/PPU_palettes
- Standard controller (the buttons' report order, the masks the menu reads) —
  https://www.nesdev.org/wiki/Standard_controller
- Cycle reference chart (60.0988 frames per second) — https://www.nesdev.org/wiki/Cycle_reference_chart
- raylib cheatsheet (textures, text) — https://www.raylib.com/cheatsheet/cheatsheet.html
- libretro-thumbnails (artwork, not planned) — https://github.com/libretro-thumbnails/libretro-thumbnails
- Plans 16 (headless), 18 (window), 34 (data directory), 35 (save states), 36 (gamepad)
