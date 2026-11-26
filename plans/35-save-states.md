# 35 — Save states

**Status:** done (2026-11-25)

**Depends on:** 34 (the data directory)

## Goal

Save the whole machine at any moment and come back to that exact moment later, even in games that have no save of
their own. Each save state is a slot of a game, with a picture of the moment it was saved.

## Context

- **Finding (probe, 2026-11-24, outside the repository).** `Marshal.dump` of a `Console` running Super Mario
  Bros. 3, after 300 frames, gave 1,265,190 bytes. The restored copy and the original, each run 120 more frames,
  ended on the same frame digest. The emulator's state is plain Ruby objects (integers, arrays, the components and
  their collaborators), with no Proc or IO inside, so Marshal can carry it whole.
- **Findings (probe, 2026-11-25, inside the repository, Ruby 4.0.10 under YJIT):**
  - The console does not keep its `Cartridge`. Only the board does: `@prg_rom`, and `@chr` when it is CHR ROM.
    Walking the console's object graph found no other reference to them, so the board is where the ROM is left out.
  - Super Mario Bros. 3 after 300 frames:
    - the dump is 1,265,209 bytes, 9.4 ms;
    - the PRG ROM is 649,821 bytes of it and the CHR ROM 321,652;
    - the two frame buffers (`Ppu::Picture`) are 122,886 bytes each.
  - Without the ROM, the dump compressed by zlib at its default level:

    | Game | Board | Dump | zlib | zlib time |
    |---|---|---|---|---|
    | Bomberman II | MMC1 | 313,693 | 11,706 | 1.8 ms |
    | Castlevania | UxROM | 296,899 | 21,464 | 3.5 ms |
    | The Legend of Zelda | MMC1 | 316,491 | 24,299 | 4.0 ms |
    | Mario Bros. | NROM | 294,225 | 9,481 | 1.6 ms |
    | Super Mario Bros. 3 | MMC3 | 296,065 | 16,805 | 3.5 ms |
    | Super Pitfall | UxROM | 298,989 | 22,823 | 3.9 ms |

  - **The graph's shape is stable.** The set of "class and instance variable names" of every object reachable from
    the console (66 to 68 classes) was the same at frames 1, 30, 300 and 900, with random input, in all six games.
    Every object is built at power-up: the hot path rules forbid allocating later.
  - A PNG of a frame (`Frontends::Palette.rgb` + `Frontends::Png`) takes about 2 ms.
- **Marshal builds a new console**, while `Frontends::Driver` and `Saves::BatteryKeeper` keep the one they were given.
  So a state is restored into the console the window runs, which swaps its components for the loaded ones.
- **Safety.** "Never use Marshal.load on untrusted data" (Ruby's Marshal documentation): loading a file can build any
  object. So states are only loaded from the emulator's own directory, and the README says not to load states from
  others.
- The window has a hotkey layer (`Frontends::Hotkeys`, actions bound in the key config). `Frontends::Driver` already
  resets the console between frames, and loading a state between frames fits the same place.
- `Frontends::Png` writes the thumbnail. Plan 37's ROM list can show the last state's picture as the game's preview.

## Scope

In:

1. **A console state:**
   - the console's components written as bytes (Marshal, compressed with zlib), without the ROM;
   - behind a header with a format version, the ROM's SHA-256 and the shape fingerprint (decision 2);
   - loading checks the header and refuses a state of another ROM, of another shape or a damaged one with a message,
     never a crash.
2. **Slots per game** under the data directory of plan 34, each slot a state file and a PNG of its frame.
3. **Hotkeys:** save to the current slot, load it, next and previous slot (decision 3), with a short message drawn over
   the picture ("State 3 saved").
4. **After a load, the audio queue starts over**, so no stale sound plays.
5. **A spec that keeps it working:** from a state saved at frame N, the restored console runs to the same frame digests
   and the same audio samples as the console that was never interrupted. It runs on a cartridge built in memory, on a
   test ROM (`test_rom:`) and on SMB3 (`local_rom:`) when available.

Out:

- rewind;
- states shared between machines or versions;
- a state browser: plan 37 shows the thumbnails, and plan 38's pause menu may list the slots.

## Decisions

Settled with the user on 2026-11-25:

1. **What is written: Marshal of the console's components, the ROM left out by the board.**
   - `Mappers::Base#marshal_dump` writes every instance variable but puts nil in place of the PRG ROM, and of CHR
     when it is ROM. CHR RAM is state and goes in. The nil keeps the variable in its place, so a restored board has
     the shape of a new one (YJIT's inline caches).
   - `Console#restore` loads the components, gives the loaded board its cartridge's ROM back
     (`Mappers::Base#reattach_rom`) and swaps them in. The console stays the same object, so nothing that holds it
     needs telling.
   - The alternative, a hand-written `state`/`restore` on every component, was discarded: every later change would
     have to keep it up to date, and the probe shows Marshal is exact.
2. **Compatibility: a shape fingerprint.**
   - The header holds:
     - magic bytes;
     - the format's version;
     - the SHA-256 of the PRG ROM and the CHR ROM;
     - a fingerprint of the console's shape: the SHA-256 of the sorted, distinct lines "class name, sorted instance
       variable names" of every object reachable from it.
   - Loading compares the ROM and the shape with the running console's before `Marshal.load` runs. A state whose shape
     changed is refused: one built by older code would leave a new variable nil and crash, or run wrong. A state saved
     before a fix that kept the shape still loads.
   - (Review) The header also holds the sample rate, 0 without sound. A console with sound holds more objects than one
     without, so a state saved with `--no-audio` is refused with the sound on, and the other way round. The refusal
     names `--no-audio`, rather than claiming another version.
   - (Review) The fingerprint also covers the values of the core's constants (`Saves::ConstantsDigest`, every
     constant of `Ruby::Nes` except the frontends, saves, command line and debug, as `inspect` writes it). A state
     carries the tables the console points at (`VISIBLE_LINE`, `WAVEFORMS`, `FOUR_STEP_CYCLES`…) by value, so it is
     refused after any change to one of them.
   - (Review) A snapshot Marshal still cannot load (a change the fingerprint does not see: a `Data`'s members, a Hash's
     keys) is refused as well, never a crash.
   - Discarded:
     - the gem's version alone: it is 0.1.0 and never changes while the code does;
     - a digest of the core's sources: it refuses every state after any change, even to a comment.
3. **Keys:** F5 saves to the current slot, F7 loads it, and F6/F8 pick the previous/next slot. There are 10 slots
   (0-9), wrapping around. This is the layout several emulators use, and the keys stay configurable.
4. **Saving over a slot replaces it at once**, and the message names the slot.
5. **A game starts on its most recently saved slot**, or slot 0 when it has none, so F7 right after opening resumes
   where the player left off. Plan 37 can find the last state's picture the same way.
6. **The battery RAM follows the state.** A state holds the whole board, its battery-backed PRG RAM included, so after a
   load the RAM is the state's. `Saves::BatteryKeeper` then writes the `.sav` at its next interval, as other emulators
   (FCEUX) do. Leaving the RAM out would not return the game to the moment saved.
7. **Files:**
   - Each state is written to `states/<ROM file name>/<slot>.state` under the data directory, with `<slot>.png`
     beside it.
   - Writes are atomic, as plan 34's battery saves: `Saves::AtomicFile`, extracted from `Saves::BatteryFile`.
8. **After a load the frontend drops the audio it has queued** (`Frontends::AudioPacing#clear`).
9. **A message over the picture for 120 frames** (about 2 s), shown whether the frame rate overlay is on or off:
   - "State 3 saved", "State 3 loaded", "State 3 is empty" and "Slot 4";
   - the refusals, which say why.

   A file that cannot be written or read is a message too, plus a warning on the error output, and the game goes on.
10. **Headless runs never touch states.** `Frontends::Driver` defaults to `Driver::NoStates`, as it defaults to
    `Driver::NoFrameObserver`, so the driver needs nothing from `Saves`.

## Tasks

- [x] Probe again inside the repository: what the dump holds, size with and without the ROM, compressed.
- [x] The board leaves its ROM out of a dump and takes it back (`Mappers::Base`), TDD.
- [x] `Console#snapshot` / `#restore`, with the exactness examples, TDD.
- [x] `Saves::Shape` and `Saves::ConstantsDigest` (the fingerprint), TDD.
- [x] `Saves::AtomicFile`, extracted from `Saves::BatteryFile`.
- [x] `Saves::ConsoleState` (header, compression, refusals), TDD.
- [x] `Saves::Directory#states_folder`, TDD.
- [x] `Saves::StateFiles` (the slots' files, the latest slot) and `Saves::StateSlots` (the player's actions), TDD.
- [x] `Frontends::Screenshot`, extracted from `Frontends::Headless`.
- [x] Hotkeys and the key config's defaults, TDD.
- [x] `Frontends::Base` and `Frontends::Driver` (with `Driver::NoStates`), TDD.
- [x] `Frontends::Notice`, `Frontends::AudioPacing#clear` and the window's message, TDD.
- [x] `CommandLine::Window` wiring, TDD.
- [x] README (Playing: keys, save states, the Marshal warning), `docs/architecture.md` (Frontends, Layout, decisions
      107-109) and `docs/benchmarks.md`.

## Acceptance criteria

- [x] Saving and loading in the window returns the game to the exact moment, sound included, in every board with a
      local ROM: SMB3 (MMC3), Zelda (MMC1), Castlevania (UxROM) and Mario Bros. (NROM). Played by the user, with the
      states and pictures written under `~/.local/share/ruby-nes/states/`.
- [x] A restored console runs to the same frame digests and audio samples as one never interrupted (spec: a program
      built in memory, the MMC3 scanline timing test ROM, and SMB3 from frame 1250 for 120 frames).
- [x] A state of another ROM, of another shape, or a damaged one is refused with a message (spec).
- [x] A state file is small (no ROM inside): 9,335 to 17,977 bytes on the six local games after 600 frames (SMB3:
      15,466), against SMB3's 1,265,209-byte dump with the ROM; its picture is 259 to 5,604 bytes.
- [x] `rake bench:frames` keeps its digests and its speed (nothing on the hot path changes), and a restored console runs
      as fast as a new one (probe). `bench/frame.rb` under YJIT, interleaved with the base commit: 11.09 and 11.14 ms a
      frame against the base's 10.90 and 11.16, digests f0903fbc59bf / 10369a5b40df; restored consoles in
      `docs/benchmarks.md`.
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green (3062 examples, 0 failures; 435 files, no offenses), branch
      coverage of each new unit, rubocop clean.

## What was done

- `Console#snapshot` / `#restore` marshal the console's components and swap them in place; `Mappers::Base` leaves the
  ROM out of its dump and gets it back with `reattach_rom`. A restored console runs to the same frame digests and
  audio samples as one never interrupted (a program in memory, the MMC3 scanline timing test ROM, SMB3).
- `Saves::ConsoleState` writes a header (magic, format, ROM digest, sample rate, code fingerprint from
  `Saves::Shape` and `Saves::ConstantsDigest`) and the zlib-compressed snapshot, and refuses any state that does not
  match with a reason, before `Marshal.load`; states are 9-18 KB.
- `Saves::StateFiles` and `Saves::StateSlots` keep 10 slots per game under `states/<ROM name>/` (state and PNG
  picture, written through `Saves::AtomicFile`, now shared with `BatteryFile`); a game starts on its latest slot.
- F5 / F7 / F6 / F8 (configurable) save, load and pick the slot; `Frontends::Driver` hands the action to the slots
  between frames, the window shows the outcome for 120 frames (`Frontends::Notice`) and drops queued audio after a
  load. Headless runs never touch states (`Driver::NoStates`).
- Review: the sample rate joined the header (a state saved with or without `--no-audio` is refused naming it), and
  the core's constants joined the fingerprint, since a state carries their tables by value.

## References

- Ruby's Marshal, its format, `marshal_dump`/`marshal_load` and its security note —
  https://docs.ruby-lang.org/en/master/Marshal.html
- Plan 34 (the data directory, atomic writes), plan 16 (`Frontends::Png`, the headless screenshots), plan 18
  (hotkeys), plan 24 (audio pacing)
