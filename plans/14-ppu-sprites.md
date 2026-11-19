# 14 — PPU sprites

**Depends on:** 13

## Goal

Sprites over (or behind) the background: OAM evaluation, the 8-per-scanline limit and overflow flag, sprite pattern
fetches, 8×16 mode, flips, priority, and sprite 0 hit.

## Context

- OAM: 64 sprites × 4 bytes (Y, tile, attributes, X). Attributes: palette (bits 0–1), priority behind background
  (bit 5), flip H (bit 6), flip V (bit 7). Y is one less than the screen line.
- Evaluation (dots 65–256) selects up to 8 sprites for the **next** scanline into secondary OAM; a 9th sets the
  overflow flag — with the hardware's buggy diagonal scan.
- Fetches for the selected sprites happen at dots 257–320; OAMADDR is reset to 0 during those dots.
- 8×16 sprites: pattern table chosen by tile bit 0, not by PPUCTRL.
- Priority between sprites: lower OAM index wins (even if it is behind the background).
- Sprite 0 hit: set when an opaque pixel of sprite 0 overlaps an opaque background pixel, with rendering of both
  enabled, not at x = 255, not in the left 8 pixels when either is clipped; cleared at pre-render dot 1.

## Scope

In: everything above, writing into the same frame buffer.

Out: OAM decay and other analog behaviour.

## Open decisions

- Overflow flag: implement the buggy evaluation exactly (recommended: some games rely on it, and `sprite_overflow_tests`
  check it) or set it on the simple 9th sprite.
- Evaluation per dot vs per scanline at dot 257 (results are the same unless a game writes OAM mid-evaluation).
  Recommendation: per scanline, documented.

From plan 11: `Ppu::Oam` holds the 256 bytes (byte 2 already ANDed with `$E3` on write) and OAMADDR; OAMDATA
writes increment it, reads do not. Left to this plan: the sprite 0 hit and overflow bits of `$2002` (0 until now),
OAMADDR set to 0 during dots 257–320, and OAMDATA reads and writes during rendering ("glitchy increment",
"expose internal OAM accesses", PPU registers).

## Tasks

- [ ] Specify and test evaluation (0, 1, 8, 9 sprites on a line; Y boundaries; 8×16 height).
- [ ] Specify and test pixel composition: transparent sprite, sprite in front, sprite behind, sprite-sprite priority,
      flips in both modes, left clipping.
- [ ] Specify and test sprite 0 hit including each exclusion (x = 255, clipping, rendering off, transparent pixel).
- [ ] Add `sprite_hit_tests_2005.10.05` and `sprite_overflow_tests` to the manifest.

## Acceptance criteria

- [ ] `sprite_hit_tests_2005.10.05` basics, alignment, corners, flip, left clip, right edge, screen bottom and double
      height pass; timing ROMs recorded in `docs/test-roms.md` with results.
- [ ] `sprite_overflow_tests` basics pass; others recorded.
- [ ] 100% branch coverage on sprite code; rubocop clean.

## References

- PPU OAM — https://www.nesdev.org/wiki/PPU_OAM
- PPU sprite evaluation — https://www.nesdev.org/wiki/PPU_sprite_evaluation
- PPU sprite priority — https://www.nesdev.org/wiki/PPU_sprite_priority
- PPU rendering (sprite fetches) — https://www.nesdev.org/wiki/PPU_rendering
- Sprite 0 hit — https://www.nesdev.org/wiki/PPU_OAM#Sprite_zero_hits
