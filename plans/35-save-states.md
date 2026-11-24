# 35 — Save states

**Status:** todo

**Depends on:** 34 (the data directory)

## Goal

Save the whole machine at any moment and come back to that exact moment later, even in games that have no save of
their own. Each save state is a slot of a game, with a picture of the moment it was saved.

## Context

- **Finding (probe, 2026-11-24, outside the repository).** `Marshal.dump` of a `Console` running Super Mario
  Bros. 3, after 300 frames, gave 1,265,190 bytes. The restored copy and the original, each run 120 more frames,
  ended on the same frame digest. The emulator's state is plain Ruby objects (integers, arrays, the components and
  their collaborators), with no Proc or IO inside, so Marshal can carry it whole.
- What that leaves to design:
  - **Size.** The dump carries the ROM (PRG and CHR) and every table the components hold. The state needs only what
    changes: the ROM can be left out and reattached on load.
  - **Compatibility.** Marshal writes instance variables by name. A state saved by another version of the emulator
    may load into a console whose shape changed, and run wrong rather than fail.
  - **Safety.** "Never use Marshal.load on untrusted data" (Ruby's Marshal documentation): loading a file can build
    any object. States are only loaded from the emulator's own directory, and the README says not to load states from
    others.
- The window has a hotkey layer (`Frontends::Hotkeys`, actions bound in the key config), and `Frontends::Driver`
  already resets the console between frames. Loading a state between frames fits the same place.
- `Frontends::Png` writes the thumbnail. Plan 37's ROM list can show the last state's picture as the game's preview.

## Scope

In:

1. A console state: the console written as bytes (Marshal, compressed with zlib), without the ROM, behind a header
   with a format version, the emulator's version or a shape fingerprint (open decision 2), and the ROM's SHA-256.
   Loading checks the header and refuses a state of another ROM or another shape with a message, never a crash.
2. Slots per game under the data directory of plan 34, each slot a state file and a PNG of its frame.
3. Hotkeys: save to the current slot, load it, next and previous slot (open decision 3), with a short message drawn
   over the picture ("State 3 saved").
4. After a load, the audio queue starts over, so no stale sound plays.
5. A spec that keeps it working: from a state saved at frame N, the restored console runs to the same digests as the
   console that was never interrupted (`test_rom:` on a test ROM; `local_rom:` on SMB3 when available).

Out: rewind; states shared between machines or versions; a state browser (plan 37 shows the thumbnails, plan 38's
pause menu may list the slots).

## Open decisions

1. **What is written.** (a) Marshal of the console, with the ROM left out through the cartridge's own
   `marshal_dump`/`marshal_load`. (b) An explicit `state`/`restore` method on every component, so the format is
   hand-written and stable, at the cost of every component and every later change keeping it up to date.
   Recommendation: (a), the probe shows it is exact; (b) only if a component holds something Marshal cannot write.
2. **Compatibility check.** (a) The gem's version plus a fingerprint of the classes' instance variable names, computed
   at load time, which refuses exactly the states whose shape changed. (b) The gem's version alone, which refuses
   every state after any release. (c) No check. Recommendation: (a).
3. **Keys.** (a) F5 saves, F7 loads, F6/F8 pick the previous/next slot, 10 slots (0-9). (b) Shift+1..9 saves to a slot
   and 1..9 loads it. Recommendation: (a), the layout several emulators use; the keys stay configurable.
4. **Overwriting.** (a) Saving over a slot replaces it at once. (b) It asks first. Recommendation: (a), with the
   message saying which slot it was.

## Tasks

- [ ] Probe again inside the repository: what the dump holds, size with and without the ROM, compressed.
- [ ] The console state (dump, header, load, refusals), TDD.
- [ ] Slots and thumbnails in the data directory, TDD.
- [ ] Hotkeys and the message over the picture, TDD.
- [ ] The exactness spec (save at N, restore, same digests).
- [ ] README (Playing: keys) and `docs/architecture.md` (decisions log: Marshal, safety, compatibility).

## Acceptance criteria

- [ ] Saving and loading in the window returns the game to the exact moment, sound included, in every supported
      mapper.
- [ ] A restored console runs to the same digests as one never interrupted (spec).
- [ ] A state of another ROM, or of a console whose shape changed, is refused with a message.
- [ ] A state file is small (no ROM inside); its size is recorded in the plan.
- [ ] `rake bench:frames` keeps its digests and its speed (nothing on the hot path changes).
- [ ] `bundle exec rake` green, branch coverage of each new unit, rubocop clean.

## References

- Ruby's Marshal, its format and its security note — https://docs.ruby-lang.org/en/master/Marshal.html
- Plan 34 (the data directory), plan 16 (`Frontends::Png`), plan 18 (hotkeys)
