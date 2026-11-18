# 02 — Test ROM harness

**Status:** done (2026-11-17)

**Depends on:** 00

## Goal

Make the community test ROMs available to the suite reproducibly, without committing them, survive the loss of the
upstream collection, run them in CI, and give integration specs a way to declare they need one.

## Context

Correctness of an emulator is proven mostly by test ROMs written by the community: `nestest` (CPU, with a reference
trace log), blargg's suites (CPU instructions, timing, PPU VBlank/NMI, sprite hit, MMC3, APU), and others. They are
collected in `christopherpow/nes-test-roms`.

State of the collection when this plan started (2026-11-17): last push 2022-03-02 (commit
`95d8f621ae55cee0d09b91519a8989ae0e64753b`), not archived, 96 forks, **no license file in the repository** (each suite
states its own terms in its readme). `other/nestest.nes` (24592 bytes) and `other/nestest.log` (859167 bytes) are at
the paths this plan expected.

Many blargg tests report through memory: `$6000` holds a status byte (`$80` = running, `$81` = needs reset, `< $80` =
final result, `0` = pass), `$6001-$6003` hold the signature `DE B0 61`, and `$6004+` holds a zero-terminated text
message. The reader for that protocol is built in plan 12: these ROMs wait for the PPU's VBlank flag before running.

## Scope

In:

- Infrastructure: `gh` installed globally with mise; a private GitHub repository `ruby-nes` as `origin`; a public fork
  `bvicenzo/nes-test-roms` of the collection as a fallback source.
- A manifest (`spec/fixtures/test_roms.yml`) with the pinned commit, the ordered list of sources (upstream, then the
  fork) and every ROM the suite uses with its path in the collection and its SHA-256.
- Test tooling in `spec/support/test_roms/` (not shipped in the gem; the path follows the constant):
  - `TestRoms::Entry` — a manifest file: path and checksum; whether some content matches it; whether the local copy
    is intact.
  - `TestRoms::Manifest` — loads the YAML; entries, lookup by path, candidate URLs per entry in source order.
  - `TestRoms::Downloader` — `Net::HTTP` GET; a non-200 response or a connection failure raises
    `TestRoms::DownloadError`.
  - `TestRoms::Sources` — tries the manifest's sources in order for one file and returns the first content that
    matches the checksum; raises `TestRoms::FetchError` naming the file and each source's failure when none does.
  - `TestRoms::Fetcher` — skips intact files; gets missing or corrupted ones from `Sources`; writes atomically;
    reports each file as up to date or downloaded.
  - `TestRoms::Requirement` — given the paths an example declares, returns a skip reason naming the rake task when
    one is missing or corrupted; a path absent from the manifest raises (a typo must never become a silent skip).
  - `TestRoms::ExampleGroups.install` — RSpec metadata `test_rom: <path or paths>` on a group, a nested group or an
    example: an unlisted path fails when the spec is defined; an example needs every ROM declared on it and its
    groups, and is skipped with the reason when one is unavailable; helper `test_rom_path(path)` only for declared
    paths. Its spec runs examples in an RSpec sandbox (`TestRoms::SandboxedGroup`).
- `rake test_roms:fetch` (idempotent) and `rake spec:test_roms` (only tagged groups), in `rakelib/test_roms.rake`.
- CI on GitHub Actions: fetch the test ROMs (cached, keyed on the manifest's hash), then `bundle exec rake`.
- `docs/GLOSSARY.md`: ROM and RAM entries (first plan to use "ROM" in names).

Out: anything that executes a ROM.

## Decisions

Settled with the user on 2026-11-17.

1. **Download mechanism: individual files via `Net::HTTP`.** Stdlib only, small download, one checksum per file.
2. **Mirror: an ordered list of sources.** Every file is verified by SHA-256, so any source serving the same bytes is
   as good as the upstream. The manifest lists the upstream and then the user's public fork, both at the pinned
   commit; the first source that delivers matching content wins. A fork of a public repository cannot be private,
   and a public one needs no token in CI. Vendoring the ROMs was rejected: the collection has no license file and
   `*.nes` is never committed in this project.
3. **A corrupted local file is re-downloaded.** It is treated as missing; the task fails only if no source delivers
   matching content, naming the file and each source's failure. Downloads go to a temporary file renamed into place,
   so a bad download never replaces a file.
4. **CI now, with a cache.** The project had no remote and no CI; the user chose to create a private GitHub
   repository and a GitHub Actions workflow in this plan. The test ROM directory is cached with the key
   `test-roms-${{ hashFiles('spec/fixtures/test_roms.yml') }}`. The fetch checks every checksum on a cache hit too
   (a damaged file is downloaded again for that run), and a cache is saved only after a successful job, so a bad copy
   is never stored. The Ruby version comes from `mise.toml` (ruby/setup-ruby reads it).
5. **`gh` is installed globally with mise** (`mise use -g gh@2.104.0`): a personal tool, not a project dependency.
6. **The fetch stops at the first file no source delivers.** Files written before it stay (each write is atomic).
   Reason: when every source fails it is almost always the network, and the other files would fail the same way.
7. **Source resolution is its own unit (`Sources`).** The `Fetcher` spec tree crossed the local state (intact,
   missing, corrupted) with the source outcome (first serves, a later one serves, none does), repeating the same
   subtree; splitting leaves the `Fetcher` deciding only about the local file.
8. **The skip checks integrity, not only presence.** A corrupted ROM is skipped with the same message as a missing
   one. The files are hashed once per tagged group and once per example (about 3 ms for nestest.log, 859 KB); no
   memoisation until a suite with many examples per ROM shows the cost.
9. **Branch coverage measures `spec/support/`.** SimpleCov's default `test_frameworks` profile skips all of `spec/`;
   `spec/spec_helper.rb` reloads the other default profiles and skips `spec/` except `support/`.
10. **Standard computing acronyms are allowed in tooling names** (URL, HTTP, YAML, SHA-256, SSL), expanded in a new
    "Computing terms" section of `docs/GLOSSARY.md`; `docs/architecture.md` decision 5. Reason: they are what the
    libraries and protocols call them, and `address` (the alternative to URL) already means a memory address here.

Review follow-ups (independent code review, accepted by the user):

- `test_rom:` is honoured at every level: checked against the manifest when the spec is defined
  (`define_derived_metadata`) and skipped per example (`before(:example)`); before, a nested declaration was ignored
  and a typo in it passed silently. `test_rom_path` refuses an undeclared path.
- The downloader treats malformed responses (`Net::ProtocolError`, `HTTPBadResponse`, `HTTPHeaderSyntaxError`,
  `Zlib::Error`) as a source failure, so the next source is tried; open/read timeouts are 10 s / 30 s.
- A failed write removes its partial `.download` file; the fetch yields each file as it is settled, so the files
  written before a failure are reported.
- CI reads the Ruby version from `mise.toml` and runs with `contents: read`; `TestRoms.manifest` is the one place
  that loads the manifest; misleading names (`file` for a path, `manifest` for the YAML document) were renamed.
- Not applied: treating an empty `files:` in the manifest (the manifest is ours and always lists nestest).

Second review round (accepted by the user):

- A group whose ROMs are unavailable is skipped by a `before(:context)` hook, before its own hooks run, and
  `test_rom_path` works inside group hooks (from the group's declarations), so a suite can run a ROM once per group
  (plans 08, 13). The sandbox keeps resetting `RSpec.current_example`: a skip in `before(:context)` would otherwise
  mark the caller's example.
- A bare `:test_rom` tag fails with "declare the ROM paths"; plans 08 and 13 now show `test_rom: '<path>'`.
- One source for the requirement inside the hooks; leaves for example-level declarations; `parsed_url` instead of
  `address` (decision 10); `example_body:` in the sandbox; lines over 120 columns wrapped; `TestRoms` added to the
  layout table of `docs/architecture.md`; `Fetcher#fetch` documents that its block is required.
- Not applied: memoising integrity (decision 8); hoisting the shared `let`s of the hook spec to the top-level group
  (`Vicenzo/RSpec/TopLevelLet` forbids it) or sharing one `subject` through an overridden `let` (a hidden premise).

Adding a ROM later (plans 12, 19, 20…): add its path and SHA-256 to the manifest; the code does not change. If a
path moved in the collection, adjust the manifest, not the code.

## What was done

- Infrastructure: `gh` 2.104.0 installed globally with mise; private repository `bvicenzo/ruby-nes` as `origin`;
  public fork `bvicenzo/nes-test-roms` serving the same bytes at the pinned commit.
- `spec/fixtures/test_roms.yml`: commit `95d8f621`, upstream then fork as sources, `other/nestest.nes` and
  `other/nestest.log` with their SHA-256.
- `spec/support/test_roms/`: `Entry`, `Manifest`, `Downloader`, `Sources`, `Fetcher`, `Requirement`,
  `ExampleGroups` (the `test_rom:` metadata and `test_rom_path`) and `SandboxedGroup` for the hook's own spec;
  54 examples, full branch coverage of the tooling.
- `rakelib/test_roms.rake`: `test_roms:fetch` and `spec:test_roms`.
- `.github/workflows/ci.yml`: first run downloaded the ROMs and saved the cache (32 s); the re-run restored it and
  the fetch reported both files up to date (13 s).
- `docs/GLOSSARY.md`: ROM, RAM and a "Computing terms" section; `docs/architecture.md`: decision 5 and the
  `TestRoms` layout row. Two independent code reviews; their follow-ups are listed above.

## Tasks

- [x] Install `gh` with mise; create the private `ruby-nes` repository as `origin` and push.
- [x] Fork the collection publicly; check the fork's raw files at the pinned commit match the upstream bytes.
- [x] Specify (`specify-behavior`) and test (`write-tests`) `Entry`, `Manifest`, `Downloader`, `Fetcher`,
      `Sources`, `Requirement` and the `:test_rom` hook.
- [x] Implement the rake tasks; pin the commit and both sources in the manifest.
- [x] Start the manifest with `other/nestest.nes` and `other/nestest.log`.
- [x] Gitignore `spec/fixtures/test_roms/`; keep `.github/` and `rakelib/` out of the gem's files.
- [x] Add the CI workflow with the test ROM cache.
- [x] Add ROM and RAM to `docs/GLOSSARY.md`.

## Acceptance criteria

- [x] `bundle exec rake test_roms:fetch` on a clean checkout downloads nestest and its log, and verifies checksums.
- [x] Running it twice downloads nothing the second time.
- [x] A corrupted local file is downloaded again; when no source delivers matching content, the task fails with a
      message naming the file.
- [x] With the first source unavailable, the file comes from the fork.
- [x] A `:test_rom` group with a missing ROM is reported as skipped, with the rake task name in the message; a path
      absent from the manifest fails.
- [x] `bundle exec rake spec:test_roms` runs only the tagged groups.
- [x] No test ROM is tracked by git.
- [x] CI is green on GitHub; a second run restores the cache and the fetch downloads nothing.
- [x] `bundle exec rake` green; full branch coverage of the units.

## References

- Emulator tests — https://www.nesdev.org/wiki/Emulator_tests
- nes-test-roms collection — https://github.com/christopherpow/nes-test-roms
- blargg test output protocol — described in each suite's `readme.txt` in the collection (e.g. `instr_test-v5/readme.txt`)
- GitHub Actions cache — https://github.com/actions/cache
- ruby/setup-ruby — https://github.com/ruby/setup-ruby
