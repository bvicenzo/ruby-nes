# 33 — Super Pitfall's emulation cost

**Depends on:** 32

## Goal

Find why Super Pitfall's emulation costs about 12% more a frame than Super Mario Bros. 3's under YJIT, and cut it
without changing a pixel or a sample, so it plays at 60 fps in the window too. The `rake bench:frames` digests of
Super Mario Bros. 3 (f0903fbc59bf frame, 10369a5b40df audio) and those of a Super Pitfall run taken at the start stay
unchanged.

## Context

After plan 32 the window's presentation costs about 0.8 ms a frame and Super Mario Bros. 3 plays at about 60 fps with
crackle-free audio (M7). Playing Super Pitfall (the user's dump, UxROM: iNES mapper 2, 128 KiB PRG ROM, 8 KiB CHR RAM,
vertical mirroring) the window showed about 60 fps on black screens and 48-53 fps in play. Headless under YJIT,
900 warm-up frames then 3 runs of 120 with Right held after Start, it took 23.2 ms a frame against 20.7 ms for Super
Mario Bros. 3 in the same conditions (`docs/benchmarks.md`, plan 32).

Candidates, none measured yet: the CHR RAM read path (`Mappers::Base` and the UxROM board, against MMC3's CHR ROM
windows), more sprites per line, more PPU register traffic or more CPU work per frame (the game's own loop), and
whatever the profile shows.

## Scope

In, each step prototyped and measured before it is built, kept only if it pays (plan 25, decision 4):

1. **An input script and a benchmark for Super Pitfall**: a fixture input script that plays from power-up into the
   first screens, and `bench/frame.rb` runs on it with digests (the ROM stays local, never committed).
2. **Profile** (`rake bench:profile` on that workload, vernier) and compare per component with Super Mario Bros. 3's
   profile.
3. **Cut the parts that differ**, exactly, as plans 29-31 did.

Out:

- Accuracy shortcuts (architecture decision 77).
- The window and the frame buffer contract (plan 32).

## Tasks

- [ ] Super Pitfall input script and benchmark, its starting digests recorded.
- [ ] Profile both games; record the parts that differ.
- [ ] Prototype and measure each candidate; build the kept ones test first.
- [ ] Play Super Pitfall in the window under YJIT: the frame rate and the audio.
- [ ] Record in `docs/benchmarks.md` and `docs/architecture.md`.

## Acceptance criteria

- [ ] Super Mario Bros. 3's `rake bench:frames` digests unchanged, and Super Pitfall's starting digests unchanged.
- [ ] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green.
- [ ] Super Pitfall in the raylib window at 60 fps under YJIT with audio free of crackles, or the remaining gap
      quantified per component.

## References

- UxROM — https://www.nesdev.org/wiki/UxROM
- CHR RAM — https://www.nesdev.org/wiki/CHR_ROM_vs._CHR_RAM
- iNES header — https://www.nesdev.org/wiki/INES
