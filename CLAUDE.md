# ruby-nes

A Nintendo Entertainment System emulator in pure Ruby 4.0.9. It is a study project: the goal is to learn the NES
hardware and to exercise modern Ruby (YJIT, ZJIT, Ractor-free single-threaded design, and an AOT experiment with
matz/spinel) — not to ship a product. The reference target is Super Mario Bros. 3 (mapper 4 / MMC3).

## Language

- **Conversation in Portuguese (pt-BR).** Whenever a plan is discussed, presented, started or reviewed, present it to
  the user in Portuguese.
- **Persisted artifacts in English:** plans, code, comments, commit messages, spec descriptions.

## Plans

The work is driven by the plans in `plans/` (index and status in `plans/README.md`). Execute them in order unless a
plan's "Depends on" says otherwise. Each plan is self-contained: goal, scope, design notes, tasks, acceptance criteria
and references (mostly the NESdev Wiki). When executing a plan:

1. Present it to the user in Portuguese and confirm before starting.
2. Follow the TDD workflow below for every unit.
3. A plan is done only when every acceptance criterion is checked; update its status in `plans/README.md`.
4. If a plan turns out to be wrong or incomplete, edit the plan (and say so) instead of silently diverging.

## TDD workflow

For every unit with behaviour:

1. Describe the intended behaviour in prose (domain language, including what must NOT happen).
2. Run the `specify-behavior` skill to get the spec tree (pending examples) and its open decisions.
3. Resolve open decisions with the user, then run the `write-tests` skill to fill the tree.
4. Watch it fail, implement, get it green.
5. Branch coverage pass: `COVERAGE=1 bundle exec rspec <file>` (SimpleCov, branch coverage, report in `coverage/`).
6. `bundle exec rubocop` clean on every touched file.

Hardware facts asserted in specs must come from the referenced documentation, never from memory; cite the NESdev page
in the plan when a spec rests on a quirk.

## Code style

Follow the `ruby-code-style` skill. RuboCop config inherits `rubocop-vicenzo: config/style.yml`. Never run
`rubocop -A` to fix `Layout/LineLength`.

**[`docs/architecture.md`](docs/architecture.md) is the single source of truth** for the architecture and the
conventions: components, buses, clock model, layout (constant → path), hot paths and their rules, readability, frame
buffer contract, decisions log. Acronyms and bit-operation tags are in [`docs/GLOSSARY.md`](docs/GLOSSARY.md). The
summary below is a reminder; read the document before writing code.

### Readability (summary of `docs/architecture.md` § Readability)

- No single-letter or meaningless names; no abbreviations or acronyms, except documented hardware names (`Cpu`, `Ppu`,
  `Oam`, `PPUCTRL`) expanded in `docs/GLOSSARY.md`.
- Named methods over operator-like ones (`first.intersection(second)`); flag tests always with
  `anybits?`/`allbits?`/`nobits?`; magic numbers as named constants citing NESdev.
- Bit arithmetic off hot paths goes through `Ruby::Nes::Bits` helpers. On hot paths it is inline, with named constants
  and a tag naming the readable operation: `value & BYTE_MASK # glossary: wrap-to-byte`.
- A hot path is anything called per CPU instruction, bus access, PPU dot or APU tick: integers, preallocated arrays, no
  allocation per cycle, no metaprogramming.

### Design

A large spec tree from `specify-behavior` (more than ~10–12 leaves for one unit, contexts nested deeper than 3, or a
combinatorial repetition of the same condition) means the unit makes too many decisions: split it before writing the
tests. The tree only shrinks through a change in the code: never flatten it cosmetically (two conditions merged into
one `context`, a condition moved into the `it` sentence) to fit the heuristic. When nothing can reduce the code's
complexity (a hardware rule, for instance), keep the tree as deep and wide as it is: it exists to expose that
complexity. Tell-don't-ask, strategy/polymorphism and lookup tables are the preferred tools, not mandatory ones. A long
but flat tree of data rows (one example per opcode) is not a design smell.

## Implementing a plan

Use the global skill `/implement-plan [NN]` (`~/.claude/skills/implement-plan/`, outside this repository, like the
skills it invokes): plan selection and dependency check, refinement in plan mode, TDD per unit, independent Opus code
review, commit and push.

## Commands

- `bundle exec rspec` — tests
- `COVERAGE=1 bundle exec rspec` — tests with branch coverage
- `bundle exec rubocop` — lint
- `bundle exec rake` — tests + lint

## Commits

Commit only when asked. Commits and PRs carry **no AI co-authorship**: no `Co-Authored-By: Claude …` trailer and no
"Generated with Claude Code" line.

## ROMs

ROM images are copyrighted and must never be committed (`*.nes` and `roms/` are gitignored). `roms/smb3.nes` is a
local symlink to the user's own dump. Freely distributable test ROMs are fetched by a rake task (plan 02) into a
gitignored directory.
