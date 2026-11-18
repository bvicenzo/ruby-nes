# 01 — Architecture and conventions

**Status:** done (2026-11-17)
**Depends on:** 00

## Goal

Fix, in writing, the component layout, the clock model, the hot-path coding rules and the naming conventions before
any emulation code exists, so every later plan builds on the same shape. Output is documentation — no behaviour.

## Context

The NES (NTSC) is a set of chips driven by one master clock (21.477272 MHz):

- CPU (Ricoh 2A03: a 6502 without decimal mode, plus the APU) at master ÷ 12 = 1.789773 MHz.
- PPU (2C02) at master ÷ 4 per dot, i.e. exactly 3 dots per CPU cycle. A frame is 262 scanlines × 341 dots; with
  rendering enabled, every odd frame skips one dot (the pre-render line jumps from dot 339 straight to (0, 0)).
  A frame is 29780.5 CPU cycles with rendering enabled, 29780⅔ with it disabled; ~60.0988 frames per second.
- The cartridge (mapper) sits on both the CPU bus and the PPU bus.

Components talk through buses: the CPU never calls the PPU directly, it reads/writes `$2000-$2007`.

## Scope

In:

- `docs/architecture.md` — the **single source of truth** for the architecture and the conventions: component
  diagram, buses, clock, clock model and upgrade path, layout (constant → path), hot paths and their rules,
  readability, frame buffer contract, concurrency, decisions log.
- `docs/GLOSSARY.md` — hardware terms (every acronym kept in names, expanded, with its NESdev page) and bit operations
  (each inline idiom with its anchor, cited from code as `# glossary: <term>`, and its `Ruby::Nes::Bits` helper).
- `CLAUDE.md` — a short summary of the readability rules and a link to both documents.
- `.rubocop.yml` — the line-length limit applies to lines carrying a `# glossary:` tag.
- Later plans touched by the layout: 03 (`Cartridge` nesting), 04 (`CpuBus` top-level), 08 (`Debug::Tracer`), 10
  (helpers vs inline operators variant).

Out: any behaviour (comes with the plans that specify it). No empty module skeletons either: each plan creates its
namespace together with its first class, so there is no dead code to keep in sync. `Ruby::Nes::Bits` is created by
the first plan that needs a helper off the hot path.

The content itself (layout table, hot-path rules, readability rules) lives only in `docs/architecture.md`; this plan
keeps the history of how it was decided.

## Decisions

Settled with the user on 2026-11-17. The current state of each decision is the Decisions log of
`docs/architecture.md`; this section is the record of why.

1. **Clock model: instruction-level catch-up.** `Cpu#step` executes one instruction and returns the cycles spent;
   `Console` then advances the PPU `cycles * 3` dots and the APU `cycles` ticks. Reason: simpler and fewer calls per
   instruction, which matters in Ruby. While an instruction runs the PPU/APU/mapper lag behind, so writes reach them
   early and reads see stale state. Upgrade path, cheaper first: catch the PPU/APU up on access to their registers or
   a mapper register; then tick on every bus access. Plan 12 decides with the `ppu_vbl_nmi` numbers; plan 21 may
   need it for the MMC3 IRQ.
2. **Memory container: `Array` of Integer** for RAM, VRAM, OAM and the frame buffer. Reason: the most readable
   option; plan 10 benchmarks it against a binary `String` and `IO::Buffer` and may change it with numbers.
3. **Readability on hot paths.** Off the hot path, bit arithmetic goes through intention-revealing
   `Ruby::Nes::Bits` helpers. On hot paths (anything called per instruction, bus access, dot or tick), operators are
   inline so no method call is paid per cycle, with named constants and a tag naming the readable operation,
   `# glossary: wrap-to-byte`, pointing at an anchor in `docs/GLOSSARY.md`. Flag tests always use
   `anybits?`/`nobits?`, hot paths included: they are C methods and RuboCop's `Style/BitwisePredicate` rejects the
   inline form. Reason: the user's proposal — keeps the hot path fast while a reader can still find the meaning; one
   glossary instead of a link per line keeps the comment short. Plan 10 measures helpers vs inline operators.
4. **Hardware acronyms in class names are kept** (`Cpu`, `Ppu`, `Apu`, `Oam`, `Dmc`…). Reason: they are the names
   the reference documentation uses, so they are what a reader searches for. Each one is expanded in
   `docs/GLOSSARY.md`, and the class comment expands its own.

Review follow-ups (code review of this plan, accepted by the user):

- Layout made explicit as constant → path: a class `X` in `x.rb`, nested constants in `x/`; buses top-level
  (`CpuBus`, `PpuBus`); tracers in `debug/`.
- Tags name intent, not expressions; the byte width `8` and the single bit `1` are not magic inside a tagged idiom.
- Stall cycles (OAM DMA, DMC fetches) documented as a second cross-component channel besides interrupt lines.
- The project `.rubocop.yml` narrows `Layout/LineLength`'s comment exemption to whole-line comments, so tagged lines
  keep the 120-column limit.

## What was done

- `docs/architecture.md`: single source of truth — components and the two non-bus channels (interrupt lines, stall
  cycles), CPU and PPU memory maps, clock table, instruction-level catch-up with the direction of its error and a
  two-step upgrade path, layout as constant → path, hot-path definition and rules, readability with its two
  exceptions, frame buffer contract, concurrency, decisions log.
- `docs/GLOSSARY.md`: 31 hardware terms with NESdev links; 14 bit-operation anchors with inline form and
  `Ruby::Nes::Bits` helper. Every hardware fact was checked against the cited NESdev pages.
- `CLAUDE.md` summarises the readability rules and links both documents; `.rubocop.yml` keeps the line-length limit
  on lines with a `# glossary:` tag.
- Plans 03, 04, 08 and 10 aligned with the layout and decision 3; the `implement-plan` skill now defers to
  `docs/architecture.md` and records the review base in the plan's status line.
- No module skeletons were created (see Scope).

## Tasks

- [x] Write `docs/architecture.md`.
- [x] Write `docs/GLOSSARY.md` (hardware terms with NESdev links; bit operations with anchors).
- [x] Summarise the readability rules in `CLAUDE.md` and link both documents.
- [x] Narrow the line-length comment exemption in `.rubocop.yml`.
- [x] Update plans 03, 04, 08 and 10 to the layout and decision 3.

## Acceptance criteria

- [x] `docs/architecture.md` exists and covers: layout as constant → path (with `debug/` and `Bits`), buses with
      address ranges, clock ratios with sources, the chosen clock model with the direction of its error and its
      upgrade path, the definition of hot path and its rules, readability with both exceptions, frame buffer
      contract.
- [x] The four decisions are recorded with the reason, here and in `docs/architecture.md`.
- [x] `docs/GLOSSARY.md` exists with "Hardware terms" and "Bit operations"; every bit operation has an anchor that a
      `# glossary: <term>` tag can cite.
- [x] `CLAUDE.md` links both documents and summarises the readability rules.
- [x] Plan 10 lists the "`Bits` helpers vs inline operators" variant.
- [x] `bundle exec rake` still green.

## References

- CPU — https://www.nesdev.org/wiki/CPU
- CPU memory map — https://www.nesdev.org/wiki/CPU_memory_map
- PPU memory map — https://www.nesdev.org/wiki/PPU_memory_map
- Cycle reference chart (clock rates, frame length) — https://www.nesdev.org/wiki/Cycle_reference_chart
- PPU frame timing (odd-frame skipped dot) — https://www.nesdev.org/wiki/PPU_frame_timing
- Catch-up (emulation technique) — https://www.nesdev.org/wiki/Catch-up
- DMA (CPU stalls) — https://www.nesdev.org/wiki/DMA
- Ruby `Data` — https://docs.ruby-lang.org/en/master/Data.html
- Ruby `IO::Buffer` — https://docs.ruby-lang.org/en/master/IO/Buffer.html
