# 34 — Battery-backed saves

**Status:** done (2026-11-25)

**Depends on:** 20 (MMC1), 21 (MMC3)

## Goal

Games that keep their progress on the cartridge (The Legend of Zelda, Final Fantasy, Kirby's Adventure, StarTropics)
keep it in ruby-nes too: the window loads the game's save file when it starts and writes it back while and after it
plays, so a game saved inside the game is there the next time it opens.

## Context

- The cartridges did it with a battery: "Cartridge contains battery-backed PRG RAM ($6000-7FFF) or other persistent
  memory" is bit 1 of the iNES header's flags 6 (iNES page). `Cartridge::Header#battery?` already decodes it.
- PRG RAM already exists: `Mappers::Base` gives a board 8 KiB at $6000-$7FFF when it is built with `prg_ram: true`
  (NROM, MMC1 and MMC3 are). MMC1's PRG bank bit 4 turns it off (`enable_prg_ram`). MMC3 ignores $A001, the PRG RAM
  protect register (plan 21, decision 4). Nothing reads the RAM's contents from outside the mapper, nothing fills it
  from a file, and `Console` does not hand its mapper out.
- Emulators save that RAM as a raw `.sav` file of its bytes (8 KiB here), so a save file can move between emulators.
- The window ends through `CommandLine::Window`, which closes the frontend however the run ends (`ensure`).
  `Frontends::Driver#run` loops until the window stops, so a write while the game plays needs a hook per frame there.
  The headless runs (specs, benchmarks, digests) must stay deterministic: nothing they run may read a save file.
- Local dumps (refinement, 2026-11-25): The Legend of Zelda (MMC1, flags 6 = $12, battery) for the manual test;
  Bomberman II (MMC1, no battery) and Super Mario Bros. 3 (MMC3, no battery) for "no file".
- Plans 35 and 37 keep their files under the same data directory, and plan 37 writes the battery save before going
  back to the ROM list and marks games that have one: the directory and the save file are units of their own, in a
  namespace outside the core, `Ruby::Nes::Saves` (`lib/ruby/nes.rb` does not load it, as with `Frontends`).

## Scope

In:

1. A mapper hands out a copy of its battery RAM's bytes and takes bytes back into it. Only boards with PRG RAM do, and
   only when the header has the battery flag: otherwise it has none (`nil`). `Console` passes both through.
2. The data directory (`Saves::Directory`): where the saves live and a ROM's save path (decisions 1 and 2).
3. A save file unit (`Saves::BatteryFile`): reads a `.sav` (a missing file is no save, and a file of the wrong size is
   an error naming it and both sizes), and writes atomically (decision 7).
4. A keeper (`Saves::BatteryKeeper`) that loads the save into the console, writes it every 300 frames when the RAM
   changed since the last write, and at the end; a null keeper for a console without a battery.
5. `Frontends::Driver` tells an optional frame observer after each frame it runs.
6. The window loads the save before it opens and writes it when the run ends (decision 4).
7. Headless runs never touch save files (decision 3).
8. The README and `docs/architecture.md` (Frontends, the mapper interface, Layout, the decisions log) say where the
   saves live.

Out: save states (plan 35); NES 2.0's PRG-NVRAM size field (`docs/architecture.md` reads iNES 1.0 fields only);
mappers' other persistent memory (EEPROM boards such as Bandai's); MMC3's $A001 protect (plan 21, decision 4 stands);
a headless `--save` option.

## Decisions

1. **Saves live in the user's data directory**, `$XDG_DATA_HOME/ruby-nes/saves/`, else `~/.local/share/ruby-nes/saves/`.
   The XDG specification: "If `$XDG_DATA_HOME` is either not set or empty, a default equal to `$HOME`/.local/share
   should be used", and "If an implementation encounters a relative path in any of these variables it should consider
   the path invalid and ignore it". The home directory is Ruby's `Dir.home` (HOME, else the user's account), as the
   key config's `~` is, and must be absolute. It is the sibling of `~/.config/ruby-nes/`, works whatever folder the
   ROMs are in, and plans 35 and 37 keep their files under it.
2. **A save is named after the ROM's file name** (`Legend of Zelda, The (USA) (Rev 1).sav`), as most emulators do,
   so a `.sav` copied from another emulator just works. Two ROMs of the same name in different folders share a save.
3. **Headless runs never load or write saves, and get no option for it.** The digests stay reproducible, and the
   window's specs run the keeper with a stand-in frontend, so no spec needs a headless save (YAGNI).
4. **The running game's save is written every 300 emulated frames (about 5 s at 60.0988 Hz) when the RAM changed since
   the last write, and when the run ends.** The keeper counts the frames the driver runs (deterministic, and a paused
   game changes nothing) and compares 8 KiB, off the hot path; a dirty flag on $6000-$7FFF writes would touch the bus.
   The end goes through `ensure`, which Ctrl+C and SIGTERM reach; a SIGKILL loses at most one interval.
5. **A save file of the wrong size is an error, raised before the window opens**: the game does not run, so the file
   is never overwritten.
6. **No save file is created until the RAM changes.** The keeper's baseline is the RAM after the load (the save, or
   the power-up zeros), so a game that never writes its RAM leaves no file.
7. **Writes are atomic**: a temporary file of its own in the same directory (a unique name created exclusively,
   `Tempfile.create`, so two windows of the same game never write into each other's), flushed to disk (`fsync`),
   renamed over the save; the directory is created when missing. A crash mid-write leaves the old save or the new
   one, never half of one. Measured on 2026-11-25: a write with its `fsync` takes about 2 ms (3.5 ms at most, btrfs on
   an SSD), against a frame of about 11 ms, so the `fsync` stays on the periodic writes too.
8. **The RAM goes out as a copy and comes in copied into the same array.** Nobody outside the board can change it,
   and the hot path keeps reading `@prg_ram`. MMC1 with its RAM off still hands the bytes out: off is the bus's, not
   the memory's. Bytes of another size than 8 KiB are an `ArgumentError` (plan 35 will reuse the setter).
9. **(Review) A console without battery RAM never asks the saves directory anything**: `BatteryKeeper.for(console:,
   directory:, rom_path:, error_output:)` returns `Saves::NoBattery` first, so a game without a battery needs no home
   directory. **A periodic write that fails is a warning** on the error output and the game goes on, trying again the
   next interval; the write at the end raises.

## Tasks

- [x] `Mappers::Base#battery_ram` / `#battery_ram=`, TDD.
- [x] `Console#battery_ram` / `#battery_ram=`, TDD.
- [x] `Saves::Directory`, TDD.
- [x] `Saves::BatteryFile` (read, wrong size, atomic write), TDD.
- [x] `Saves::BatteryKeeper` (load, every 300 frames, at the end, null keeper), TDD.
- [x] `Frontends::Driver`'s frame observer, TDD.
- [x] `CommandLine::Window` wiring, with a `local_rom:` example (Bomberman II writes no file), TDD.
- [x] The headless run touches no save, TDD.
- [x] README (Playing) and `docs/architecture.md` (Frontends, mapper interface, Layout, decisions log).

## Acceptance criteria

- [x] A battery game's save, made inside the game, is there after quitting and opening the game again (manual test
      with the user's Zelda dump, 2026-11-25: the name at once, the sword after a Game Over's SAVE).
- [x] Killing the process while playing loses at most one interval of progress (300 frames), and never leaves a broken
      save (atomic write, specified; the interval and the atomic write are specified, a `kill -9` was not tried by
      hand).
- [x] A game without the battery flag creates no file (specified, and a `local_rom:` example with Bomberman II).
- [x] `rake bench:frames` keeps its digests, and a headless run touches no save file.
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green, branch coverage of each new unit, rubocop clean. One failure on
      the Linux machine it ran on, not of this plan: `raylib_picture_spec.rb:33` (a shader that should not link links
      under that GPU driver) fails on the base commit too.

## What was done

- **The board's RAM out and in:** `Mappers::Base#battery_ram` hands a copy of the 8 KiB of PRG RAM when the board has
  some and the header the battery flag (else nil), whether MMC1 turned it off or not; `#battery_ram=` copies a save's
  8 KiB in, in the array the CPU reads, and refuses another size. `Console` passes both through.
- **`Ruby::Nes::Saves`**, outside the core: `Directory` (`$XDG_DATA_HOME/ruby-nes`, else `.local/share/ruby-nes` under
  `Dir.home`; `saves/<ROM file name>.sav`), `BatteryFile` (missing is no save, another size `InvalidSave`; a write to
  a temporary file of its own, `fsync`, rename), `BatteryKeeper` (load, a write every 300 frames and at the end when
  the RAM changed, a failed periodic write only warns) and `NoBattery` for a console without battery RAM, given before
  the directory is asked anything.
- **Wiring:** `Frontends::Driver` tells a frame observer after each frame it runs (`NoFrameObserver` by default);
  `CommandLine::Window` loads the save before it opens the window and writes it before it closes it. Headless runs
  never touch saves: a spec runs a battery ROM headless beside a save and finds it unchanged.
- **Measured:** a write with its `fsync` takes about 2 ms (3.5 ms at most); Super Mario Bros. 3's digests unchanged
  (`f0903fbc59bf` / `10369a5b40df`, `bench/frame.rb` under YJIT).
- **Manual test:** The Legend of Zelda kept its file name and, after a Game Over's SAVE, its sword. Zelda's other way
  to save, Up + A on controller 2, is out of reach: the window gives controller 2 no keys (backlog).
- **Review:** applied a home-directory regression for games without a battery, unique temporary files, a warning
  instead of a stop when a periodic write fails, the setter's size check, a behavioural headless spec, a window spec
  of its wiring only, and doc fixes. Declined: a builder for the spec's save bytes, a `Console#battery?` predicate.

## References

- iNES header, flags 6 — https://www.nesdev.org/wiki/INES
- PRG RAM circuit — https://www.nesdev.org/wiki/PRG_RAM_circuit
- MMC1 (PRG RAM enable) — https://www.nesdev.org/wiki/MMC1
- MMC3 (PRG RAM protect, $A001) — https://www.nesdev.org/wiki/MMC3
- XDG Base Directory Specification — https://specifications.freedesktop.org/basedir/latest/
