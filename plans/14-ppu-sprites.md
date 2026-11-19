# 14 — PPU sprites

**Depends on:** 13

**Status:** done (2026-11-19)

## Goal

Sprites over (or behind) the background: OAM evaluation, the 8-per-scanline limit and the overflow flag with the
hardware's diagonal scan, sprite pattern fetches on their dots, 8×16 mode, flips, priority, and sprite 0 hit.

## Context

Facts below were checked against the NESdev pages in References on 2026-11-19.

[PPU OAM](https://www.nesdev.org/wiki/PPU_OAM): byte 0 is the "Y position of top of sprite"; "Sprite data is delayed
by one scanline"; "Hide a sprite by moving it down offscreen, by writing any values between #$EF-#$FF here"; "Sprites
are never displayed on the first line of the picture". Byte 1: "For 8x8 sprites, this is the tile number of this sprite
within the pattern table selected in bit 3 of PPUCTRL"; "For 8x16 sprites (bit 5 of PPUCTRL set), the PPU ignores the
pattern table selection and selects a pattern table from bit 0 of this number"; "Tile number of top of sprite (0 to
254; bottom half gets the next tile)". Byte 2: "Palette (4 to 7) of sprite", "Priority (0: in front of background; 1:
behind background)", "Flip sprite horizontally", "Flip sprite vertically"; "Flipping does not change the position of
the sprite's bounding box"; "In 8x16 mode, vertical flip flips each of the subtiles and also exchanges their position".
Byte 3: "X position of left side of sprite"; values `$F9-$FF` put "parts of the sprite to be past the right edge of the
screen, thus invisible". "Priority between sprites is determined by their address inside OAM".

[PPU sprite evaluation](https://www.nesdev.org/wiki/PPU_sprite_evaluation): "Cycles 1-64: Secondary OAM (32-byte buffer
for current sprites on scanline) is initialized to $FF". "Cycles 65-256: Sprite evaluation":

1. "Starting at n = 0, read a sprite's Y-coordinate (OAM[n][0], copying it to the next open slot in secondary OAM
   (unless 8 sprites have been found, in which case the write is ignored)"; "If Y-coordinate is in range, copy
   remaining bytes of sprite data (OAM[n][1] thru OAM[n][3]) into secondary OAM."
2. "Increment n"; "If n has overflowed back to zero (all 64 sprites evaluated), go to 4"; "If less than 8 sprites have
   been found, go to 1"; "If exactly 8 sprites have been found, disable writes to secondary OAM because it is full."
3. "Starting at m = 0, evaluate OAM[n][m] as a Y-coordinate"; "If the value is in range, set the sprite overflow flag in
   $2002 and read the next 3 entries of OAM"; "If the value is not in range, increment n **and** m (without carry). If n
   overflows to 0, go to 4; otherwise go to 3". "The m increment is a hardware bug".
4. "Attempt (and fail) to copy OAM[n][0] into the next free slot in secondary OAM, and increment n (repeat until HBLANK
   is reached)".

"Sprite evaluation does not happen on the pre-render scanline"; "no sprites will be rendered on the first scanline";
"Sprite evaluation occurs if _either_ the sprite layer or background layer is enabled via $2001". The page gives no
formula for "in range": `0 ≤ scanline − Y < height` (8 or 16) is a derivation from "delayed by one scanline" and the
evaluation being for the next line.

[PPU rendering](https://www.nesdev.org/wiki/PPU_rendering), dots 257-320: "The tile data for the sprites on the _next_
scanline are fetched here", 4 accesses of 2 dots per sprite: "Garbage nametable byte", "Garbage nametable byte",
"Pattern table tile low", "Pattern table tile high (8 bytes above pattern table tile low address)". "If there are less
than 8 sprites on the next scanline, then dummy fetches to tile $FF occur for the left-over sprites"; "the sprites are
loaded with a transparent set of values instead". The pre-render scanline makes "the same memory accesses", "for the
sprite fetches, whatever data is currently in secondary OAM". "Sprite 0 hit acts as if the image starts at cycle 2".
Priority multiplexer decision table: both transparent → "EXT in ($3F00)"; only the sprite opaque → sprite; only the
background opaque → background; both opaque → sprite if priority 0, background if 1.

[PPU sprite priority](https://www.nesdev.org/wiki/PPU_sprite_priority): "these eight sprites get drawn front (lower
index) to back (higher index) into a buffer, taking only the first opaque pixel that matches each X coordinate.
Priority does not affect ordering in this buffer but is saved with each pixel"; "the lowest-numbered unit that outputs a
non-transparent pixel always wins, regardless of front/back sprite priority".

[PPU registers](https://www.nesdev.org/wiki/PPU_registers): PPUCTRL bit 3 "Sprite pattern table address for 8x8 sprites
(0: $0000; 1: $1000; ignored in 8x16 mode)", bit 5 "Sprite size (0: 8x8 pixels; 1: 8x16 pixels)"; PPUMASK bit 2 "Show
sprites in leftmost 8 pixels of screen, 0: Hide", bit 4 "Enable sprite rendering"; PPUSTATUS bit 5 "Sprite overflow
flag", bit 6 "Sprite 0 hit flag", "automatically cleared on dot 1 of the prerender scanline". Sprite 0 hit is set "when
any opaque pixel of sprite 0 overlaps any opaque pixel of background, regardless of sprite priority"; it "cannot detect
collision at X=255, nor anywhere where either sprites or backgrounds are disabled via PPUMASK. This includes X=0..7 when
the leftmost 8 pixels are hidden"; it "can only detect one collision per frame". "OAMADDR is set to 0 during each of
ticks 257–320 (the sprite tile loading interval) of the pre-render and visible scanlines". OAMDATA writes during
rendering "do not modify values in OAM, but do perform a glitchy increment of OAMADDR"; "For emulation purposes, it is
probably best to completely ignore writes during rendering".

Pattern address: `0HNNNN NNNNPyyy` ([PPU pattern tables](https://www.nesdev.org/wiki/PPU_pattern_tables)); in 8×16 the
table is tile bit 0, the top tile is the even number and the bottom one the next (PPU OAM's 8x16 memory map). Sprite
palette entries are `$10-$1F`, bit 4 being "Background/Sprite select" ([PPU palettes](https://www.nesdev.org/wiki/PPU_palettes)).

From plan 11: `Ppu::Oam` holds the 256 bytes (byte 2 already ANDed with `$E3` on write) and OAMADDR. From plan 13: the
per-dot pipeline (`BackgroundSchedule` constant tables, `BackgroundRenderer`), `Picture` (frame buffer, palette lookup)
and `BackgroundVisibility`; the pixel of dot 1-256 goes to x = dot − 1 (decision 5).

## Test ROMs

`sprite_hit_tests_2005.10.05` and `sprite_overflow_tests` (NROM-128 with CHR RAM) report "on screen and by beeping",
not through `$6000`. Their source (`validation.a`, `runtime_rom.a`) keeps the code in `result = $f8` (1 passed, 2 and
up the failing test, 0 an internal error) and ends in `exit: jmp exit`.

## Scope

In: everything above, writing into the same frame buffer; PPUSTATUS bits 6-5; OAMADDR reset during 257-320; OAMDATA
writes ignored during rendering; a second blargg report protocol for the 2005 ROMs.

Out: OAM decay and other analog behaviour; the OAMADDR start of evaluation and the 2C02 OAM corruption; OAMDATA reads
exposing the evaluation; the garbage nametable fetches of 257-320 (plan 13, decision 6).

## Decisions

Settled with the user on 2026-11-19.

1. **The overflow flag follows the hardware's diagonal scan exactly** (step 3, m incremented without carry). Reason:
   `sprite_overflow_tests/4.Obscure` checks it and games may rely on it.
2. **Evaluation runs once per visible scanline, at dot 257**, for the next line. Reason: OAMDATA writes are ignored
   during rendering (decision 4), so OAM cannot change in the middle of the evaluation; one call per line. Cost: the
   overflow flag shows from dot 257 instead of the dot the 9th sprite is found (`3.Timing` fails), and `$2004` reads
   during rendering do not expose the evaluation (Known gaps).
3. **Sprite pattern fetches happen on their dots**: the low byte at 261 + 8k, the high byte at 263 + 8k (the access of
   a 2-dot pair on its first dot, plan 13 decision 9); empty slots fetch tile `$FF`; the pre-render line fetches from
   what secondary OAM still holds but loads nothing (no sprites on line 0). Reason: MMC3's A12 counting (plan 21).
4. **OAMDATA writes during rendering are ignored completely** (no store, no increment), as the page advises for
   emulators; reads are unchanged (Known gap).
5. **OAMADDR is set to 0 on each dot 257-320** of the visible and pre-render lines with rendering enabled. The
   evaluation always starts at sprite 0: "the sprite at OAMADDR to be treated as it was sprite 0" and the 2C02's OAM
   corruption are Known gaps.
6. **Composition follows the page's buffer model**: the selected sprites are drawn front to back into a 256-entry line
   buffer keeping the first opaque pixel with its priority and a sprite 0 mark; each dot reads one entry. One buffer is
   enough: line N's pixels end at dot 256 and line N + 1's buffer is filled from dot 257 on.
7. **Renames**: `BackgroundSchedule` → `RenderSchedule`, `BackgroundRenderer` → `Renderer` (they now run sprite steps
   too), `BackgroundVisibility` → `LayerVisibility` (the same rule, layer enabled, left 8 columns, transparent pixel,
   serves both layers: two instances, PPUMASK bits 3/1 and 4/2).
8. **`Blargg::Runner` takes its report as a strategy** (`report:`, defaulting to `Report`); `Blargg::LegacyReport`
   reads the 2005 protocol: finished once the CPU sits on an absolute `JMP` to itself, code from `$F8`. `rake
   blargg:run` picks the report by suite.
9. **Sprite 0 hit is set on the dot its pixel is composed** (x + 1), one dot before NESdev's "as if the image starts at
   cycle 2"; checked against the timing ROMs 09-11, which are recorded only.

10. **Units split while specifying (the size check of the TDD workflow)**, beyond the units first planned:
    `SpriteRows` (the "in range" rule, shared by the evaluation and the overflow search); `SecondaryOam` (storage,
    apart from the selection in `SpriteEvaluation`); `SpritePatternAddress::EightByEight` and `::EightBySixteen` (a
    strategy per sprite size, chosen by the Ppu through `SpriteRenderer#tall_sprites=`, instead of a size × half × flip
    conditional in the fetcher); the horizontal flip moved into `SpriteLine#place`, which already reads the
    attributes; `SpriteZeroHit` (apart from the multiplexer's colour choice, asked only where both pixels are opaque);
    `SpriteRenderer` (the sprite steps and settings, so `Renderer` keeps the background and the composition).
    `Bits.combine_bytes` and the spec builder `OamContents` came with them.
11. **After the independent review**: lines with rendering disabled clear the sprite line at dot 257 too, so a sprite
    loaded before a forced blank does not show again when rendering comes back (an output unit shows its row on the
    line after its fetch only); `SecondaryOam#sprite_zero?(slot)` answers for the fetcher; the sprite layout constants
    live on `Oam`, the shared ones of the two pattern address strategies on `SpritePatternAddress`, and each strategy
    gives its height, so PPUCTRL bit 5 is decoded once (`SpriteRenderer#tall_sprites=`); `Blargg::LegacyReport` reads
    the bus only in PRG ROM.
12. **The cost is recorded for plan 25**: about 28% of the frame rate under YJIT on nestest (26.6 to 19.2 frames per
    second), from three calls more per pixel and the sprite steps of dots 257-320 (architecture decision 34).

## Tasks

- [x] `Ppu::Oam#byte` and OAMDATA writes ignored during rendering.
- [x] `Ppu::SpriteRows`: the "in range" rule.
- [x] `Ppu::OverflowSearch`: step 3, the diagonal scan.
- [x] `Ppu::SecondaryOam` and `Ppu::SpriteStatus`.
- [x] `Ppu::SpriteEvaluation`: steps 1-2 into secondary OAM (0, 1, 8, 9 sprites; Y boundaries; 8×16 height; sprite 0
      selected); the overflow search when 8 are found.
- [x] `Ppu::SpriteLine`: the line buffer (first opaque pixel wins, right edge, horizontal flip, priority and sprite 0
      marks).
- [x] `Ppu::SpritePatternAddress::EightByEight` and `::EightBySixteen`: pattern addresses, vertical flip in both modes.
- [x] `Ppu::SpriteFetcher`: the slot's fetches, tile `$FF` for empty slots, loading into the line.
- [x] `Ppu::LayerVisibility` (rename) for both layers.
- [x] `Ppu::SpriteZeroHit` and `Ppu::PriorityMultiplexer`: the decision table and sprite 0 hit with its exclusions.
- [x] `Ppu::RenderSchedule` (rename) with the sprite steps; `Ppu::SpriteRenderer`; `Ppu::Renderer` (rename) running
      them and composing the pixel.
- [x] `Ppu` wiring: PPUCTRL bits 3 and 5, PPUMASK bits 2 and 4, PPUSTATUS bits 6-5 cleared at pre-render dot 1.
- [x] `Blargg::LegacyReport`, the runner's `report:`, `rake blargg:run`.
- [x] Add `sprite_hit_tests_2005.10.05` and `sprite_overflow_tests` to the manifest; passing ROMs as `slow: true`
      examples; results in `docs/test-roms.md`; a sprite frame dumped and inspected.
- [x] `docs/architecture.md` (Rendering, layout, Known gaps, decisions log), `docs/GLOSSARY.md`.

## Acceptance criteria

- [x] `sprite_hit_tests_2005.10.05` 01-08 (basics, alignment, corners, flip, left clip, right edge, screen bottom,
      double height) pass; the timing ROMs 09-11 are recorded in `docs/test-roms.md` with results (they pass too).
- [x] `sprite_overflow_tests` 1.Basics passes; the others are recorded (2, 4 and 5 pass; 3 fails #5, overflow timing).
- [x] Evaluation leaves: 0, 1, 8, 9 sprites; Y boundaries; 8×16 height; sprite 0 selected; the diagonal overflow scan.
- [x] Composition leaves: transparent sprite, sprite in front, sprite behind, sprite-sprite priority, flips in both
      modes, left clipping.
- [x] Sprite 0 hit leaves: each exclusion (x = 255, clipping, layer disabled, transparent pixel) and the clear at
      pre-render dot 1. x = 255 and sprite 0 are `SpriteZeroHit`'s leaves; a transparent pixel is
      `PriorityMultiplexer`'s (it asks only where both pixels are opaque); clipping and a disabled layer are
      `LayerVisibility`'s, whose hidden pixels reach the multiplexer as transparent; the clear is
      `Ppu#vertical_blank_ended`'s.
- [x] OAMADDR is 0 after dots 257-320; an OAMDATA write during rendering changes nothing.
- [x] 100% branch coverage on sprite code; rubocop clean; `SLOW=1 bundle exec rake` green.

## What was done

- `Ppu::SpriteEvaluation` selects up to 8 sprites per visible scanline at dot 257 into `Ppu::SecondaryOam`
  (`Ppu::SpriteRows` decides "in range"); `Ppu::OverflowSearch` scans for a ninth with the hardware's diagonal bug;
  `Ppu::SpriteStatus` holds PPUSTATUS bits 6-5, cleared at pre-render dot 1 and left by reads.
- `Ppu::SpriteFetcher` fetches each slot's pattern bytes on dots 261 + 8k and 263 + 8k (tile `$FF` for empty slots, the
  pre-render line too) through `Ppu::SpritePatternAddress::EightByEight` or `::EightBySixteen`, and loads
  `Ppu::SpriteLine`, the line buffer (first opaque pixel per column, flips, priority and sprite 0 marks).
- `Ppu::LayerVisibility` (from `BackgroundVisibility`) serves both layers; `Ppu::PriorityMultiplexer` applies NESdev's
  decision table and asks `Ppu::SpriteZeroHit` where both pixels are opaque; `Ppu::SpriteRenderer` runs the sprite
  steps of `Ppu::RenderSchedule` (from `BackgroundSchedule`) for `Ppu::Renderer` (from `BackgroundRenderer`). OAMADDR is
  0 on dots 257-320; OAMDATA writes during rendering are ignored.
- `Blargg::LegacyReport` reads the 2005 ROMs' result at `$F8`; `sprite_hit_tests_2005.10.05` 01-11 and
  `sprite_overflow_tests` 1, 2, 4 and 5 pass (3 fails on overflow timing, recorded).
- Independent review: the sprite line is now cleared on lines with rendering disabled; `SecondaryOam#sprite_zero?`;
  constants deduplicated; PPUCTRL bit 5 decoded once; `LegacyReport` reads only PRG ROM. Cost: about 28% of the frame
  rate under YJIT, recorded for plan 25.

## References

- PPU OAM — https://www.nesdev.org/wiki/PPU_OAM
- PPU sprite evaluation — https://www.nesdev.org/wiki/PPU_sprite_evaluation
- PPU sprite priority — https://www.nesdev.org/wiki/PPU_sprite_priority
- PPU rendering (sprite fetches) — https://www.nesdev.org/wiki/PPU_rendering
- PPU registers — https://www.nesdev.org/wiki/PPU_registers
- PPU pattern tables — https://www.nesdev.org/wiki/PPU_pattern_tables
- PPU palettes — https://www.nesdev.org/wiki/PPU_palettes
- sprite_hit_tests_2005.10.05 and sprite_overflow_tests readmes and sources —
  https://github.com/christopherpow/nes-test-roms
