# 34 — Battery-backed saves

**Status:** todo

**Depends on:** 20 (MMC1), 21 (MMC3)

## Goal

Games that keep their progress on the cartridge (The Legend of Zelda, Final Fantasy, Kirby's Adventure, StarTropics)
keep it in ruby-nes too: the window loads the game's save file when it starts and writes it back while and after it
plays, so a game saved inside the game is there the next time it opens.

## Context

- The cartridges did it with a battery: "Cartridge contains battery-backed PRG RAM ($6000-7FFF) or other persistent
  memory" is bit 1 of the iNES header's flags 6 (iNES page). `Cartridge::Header#battery?` already decodes it.
- PRG RAM already exists: `Mappers::Base` gives a board 8 KiB at $6000-$7FFF when it is built with `prg_ram: true`
  (MMC1 and MMC3 are). MMC1's PRG bank bit 4 turns it off (`enable_prg_ram`). MMC3 ignores $A001, the PRG RAM protect
  register (plan 21, decision 4). Nothing reads the RAM's contents from outside the mapper, and nothing fills it from
  a file.
- Emulators save that RAM as a raw `.sav` file of its bytes (8 KiB here), so a save file can move between emulators.
- The window ends through `CommandLine::Window`, which closes the frontend however the run ends (`ensure`). The
  headless runs (specs, benchmarks, digests) must stay deterministic: nothing they run may read a save file.
- None of the ROMs measured so far has a battery. A manual test needs a dump of a battery game.

## Scope

In:

1. A mapper hands out its battery RAM's bytes and takes them back. Only boards with PRG RAM do, and only when the
   header has the battery flag: a battery flag on a board without PRG RAM saves nothing.
2. A save file unit: loads a `.sav` (a missing file is an empty save, and a file of the wrong size is an error naming
   it), and writes atomically (a temporary file renamed over the old one), so a crash mid-write never leaves half a
   save.
3. The window loads the save before the first frame. It writes the save when the run ends, and also while the game
   plays, when the RAM's bytes changed since the last write (checked off the hot path, once every few seconds), so a
   crash or a killed process loses seconds, not the session.
4. Headless runs never touch save files unless asked (open decision 3).
5. The README and `docs/architecture.md` (Frontends, the decisions log) say where the saves live.

Out: save states (plan 35); NES 2.0's PRG-NVRAM size field (`docs/architecture.md` reads iNES 1.0 fields only);
mappers' other persistent memory (EEPROM boards such as Bandai's); MMC3's $A001 protect (plan 21, decision 4 stands).

## Open decisions

1. **Where the saves live.**
   - (a) In a user data directory, `~/.local/share/ruby-nes/saves/`, honouring `XDG_DATA_HOME`. It is the sibling of
     `~/.config/ruby-nes/` and works whatever folder the ROMs are in.
   - (b) Next to the ROM, as `roms/Zelda.sav`. It is easy to find and copy, but the ROM's folder must accept writes.

   Recommendation: (a). Plans 35 and 37 keep their files under the same directory.
2. **How a save file is named.**
   - (a) After the ROM's file name (`Zelda.sav`), as most emulators do, so a `.sav` copied from another emulator just
     works.
   - (b) After the ROM's SHA-256, which survives renaming the ROM but is opaque to a person.

   Recommendation: (a).
3. **Headless runs.** (a) They never load or write saves; an option such as `--save PATH` opts in, for a spec or a
   tool-assisted run. (b) They behave like the window. Recommendation: (a), so the digests stay reproducible.
4. **When the running game's save is written.** (a) Compare the RAM against the last write every few seconds (8 KiB,
   off the hot path, no change to the bus). (b) A dirty flag set on each write to $6000-$7FFF, which is a hot path.
   Recommendation: (a). The interval is settled while refining the plan.

## Tasks

- [ ] Battery RAM out of and into a mapper (`Mappers::Base`), TDD.
- [ ] The save file unit (load, atomic write, wrong size), TDD.
- [ ] The window loads at start, writes on change and at the end; the console wiring in `CommandLine`, TDD.
- [ ] Headless behaviour (decision 3), TDD.
- [ ] README (Playing) and `docs/architecture.md` (Frontends, decisions log).

## Acceptance criteria

- [ ] A battery game's save, made inside the game, is there after quitting and opening the game again (manual test
      with the user's own dump; a `local_rom:` example if a dump is available).
- [ ] Killing the process while playing loses at most one interval of progress, and never leaves a broken save.
- [ ] A game without the battery flag creates no file.
- [ ] `rake bench:frames` keeps its digests, and a headless run with no save option touches no file.
- [ ] `bundle exec rake` green, branch coverage of each new unit, rubocop clean.

## References

- iNES header, flags 6 — https://www.nesdev.org/wiki/INES
- PRG RAM circuit — https://www.nesdev.org/wiki/PRG_RAM_circuit
- MMC1 (PRG RAM enable) — https://www.nesdev.org/wiki/MMC1
- MMC3 (PRG RAM protect, $A001) — https://www.nesdev.org/wiki/MMC3
- XDG Base Directory Specification — https://specifications.freedesktop.org/basedir-spec/latest/
