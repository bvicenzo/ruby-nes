# 02 — Test ROM harness

**Depends on:** 00

## Goal

Make the community test ROMs available to the suite reproducibly, without committing them, and give integration specs
a way to declare they need one.

## Context

Correctness of an emulator is proven mostly by test ROMs written by the community: `nestest` (CPU, with a reference
trace log), blargg's suites (CPU instructions, timing, PPU VBlank/NMI, sprite hit, MMC3, APU), and others. They are
freely distributable and collected in `christopherpow/nes-test-roms`.

Many blargg tests report through memory: `$6000` holds a status byte (`$80` = running, `$81` = needs reset, `< $80` =
final result, `0` = pass), `$6001-$6003` hold the signature `DE B0 61`, and `$6004+` holds a zero-terminated text
message. The reader for that protocol is built in plan 12: these ROMs wait for the PPU's VBlank flag before running.

## Scope

In:

- `rake test_roms:fetch`: downloads a pinned commit of the collection into `spec/fixtures/test_roms/` (gitignored),
  idempotent.
- A manifest (`spec/fixtures/test_roms.yml`) listing every ROM the suite uses, with its path in the collection and a
  SHA-256, verified after download.
- RSpec metadata `:test_rom`: an example group tagged with it is skipped with an explicit message when the ROM is
  missing (pointing to the rake task), never silently passed.
- `rake spec:test_roms` to run only tagged groups.

Out: anything that executes a ROM.

## Open decisions

- Download mechanism: `git clone --depth 1` at a pinned commit vs fetching individual raw files via `Net::HTTP`.
  Recommendation: individual files via `Net::HTTP` (stdlib only, small download, checksums per file).

## Tasks

- [ ] Specify (`specify-behavior`) and test (`write-tests`) the manifest loader and checksum verification.
- [ ] Implement the rake task; pin a commit of the collection; record it in the manifest.
- [ ] Start the manifest with `other/nestest.nes` and `other/nestest.log` (verify the paths in the repository when
      executing; adjust the manifest, not the code, if they moved).
- [ ] Add the `:test_rom` skip behaviour in `spec/support/`.
- [ ] Gitignore `spec/fixtures/test_roms/`.

## Acceptance criteria

- [ ] `bundle exec rake test_roms:fetch` on a clean checkout downloads nestest and its log, and verifies checksums.
- [ ] Running it twice downloads nothing the second time.
- [ ] A corrupted file (checksum mismatch) makes the task fail with a message naming the file.
- [ ] A `:test_rom` group with a missing ROM is reported as skipped, with the rake task name in the message.
- [ ] No test ROM is tracked by git.

## References

- Emulator tests — https://www.nesdev.org/wiki/Emulator_tests
- nes-test-roms collection — https://github.com/christopherpow/nes-test-roms
- blargg test output protocol — described in each suite's `readme.txt` in the collection (e.g. `instr_test-v5/readme.txt`)
