# 16 — Frontend interface and headless backend

**Status:** done (2026-11-19)

**Depends on:** 13

## Goal

Define the contract between the emulator core and any frontend, and implement the first frontend: headless (no
window, no sound). It lets the graphics library choice be postponed (plan 17) and gives tests and benchmarks a
deterministic runner.

## Context

The core only produces a frame buffer of palette indices (plan 01) and, later, audio samples; it consumes button
states. Converting palette indices to RGB, presenting, pacing and reading the keyboard belong to the frontend.

Found when the plan started (2026-11-19):

- Greyscale is already applied by the core (plan 13: `Ppu::Picture` ANDs the colour with `$30`); only colour emphasis
  is left, and `Ppu#write_mask` ignores PPUMASK bits 5-7 so far.
- Plan 13 embedded only the first 64 colours of `2C02G_U_wiki.pal`. The whole file (1536 bytes, the same copy in
  pally's `docs/NESDev`) holds "each palette value when colour (de-)emphasis bits are applied"
  ([.pal](https://www.nesdev.org/wiki/.pal)); its first 64 colours match plan 13's byte for byte. NESdev does not give
  the order of the 8 blocks; the data does: block 1 is tinted red, 2 green, 4 blue, 7 darkened grey, so the block is
  the PPUMASK emphasis bits as a number (bit 5 = 1, bit 6 = 2, bit 7 = 4), matching "Bit 5 emphasizes red on the NTSC
  PPU", "Bit 6 emphasizes green", "Bit 7 emphasizes blue"
  ([Colour emphasis](https://www.nesdev.org/wiki/Colour_emphasis)).
  `$0F` stays black in every block ("$0F black is not" affected).
- `Console#run_frame` stops within the first instruction of the next frame, so up to the first ~21 pixels of row 0 in
  the one frame buffer already belong to it (docs/architecture.md, Frame buffer contract).
- `Debug::FrameDump` (PPM) and `rake debug:frame` would duplicate the headless frontend's PNG screenshots.

From plan 12: `Console#run_frame` returns when the PPU wraps to (0, 0) (plan 12, decision 7), so VBlank has run when
the frontend takes the frame.

## Scope

In:

- `Frontends::Base` contract (documented in the class):
  - `present(frame_buffer)` once per frame;
  - `button_states` → bitmasks for both controllers (plan 15: each bitmask goes to `Console#controllers[n].buttons=`,
    bit 0 = A … bit 7 = Right; `Input::Controller::BUTTONS` maps button names to bits);
  - `queue_audio(samples)` (no-op until plan 24);
  - `running?`.
- `Frontends::Driver`: the loop every frontend shares (button states to the controllers, `run_frame`, `present`).
- Colour emphasis in the core: a 9-bit pixel (decision 2).
- A complete frame for the frontend: double buffering in `Ppu::Picture` (decision 1).
- Shared RGB conversion, `Frontends::Palette`: the 512 colours of NESdev's `2C02G_U_wiki.pal` (decision 4).
- `Frontends::Headless`: runs N frames, takes an input script (frame number → buttons), writes PNG screenshots at
  chosen frames, exposes a digest of each frame.
- Minimal PNG encoder in pure Ruby (`zlib` from stdlib; IHDR/IDAT/IEND chunks with CRC).
- CLI first version, `Ruby::Nes::CommandLine`:
  `ruby-nes ROM --headless --frames N [--screenshot FRAME:PATH] [--input SCRIPT]`.
- Removal of `Debug::FrameDump` and `rake debug:frame` (decision 5).

Out: windowed frontends (plans 17, 18).

## Decisions

Settled with the user on 2026-11-19.

1. **Double buffering in `Ppu::Picture`.** The picture draws into a private buffer and swaps it with the published one
   (`frame_buffer`) when the PPU enters the post-render scanline 240: `Ppu::FrameTiming` tells its events
   `picture_completed` (one comparison per scanline). `Ppu#frame_buffer` is the last complete frame. Reason: O(1), no
   allocation, no copy; every visible pixel is drawn every frame (rendering or forced blank), so the back buffer is
   always overwritten whole. Changing `run_frame`'s stop point was discarded (plan 12, decision 7; the runners count
   frames by it). The array a frontend gets changes every frame: it must ask each frame.
2. **Colour emphasis in the core, a 9-bit pixel.** `Ppu` decodes PPUMASK bits 5-7 and the picture ORs them, moved to
   bits 6-8, into every pixel it stores, forced blank included: the frame buffer holds 0-511, the palette index plus
   the emphasis (bit 6 red, bit 7 green, bit 8 blue on NTSC). "The emphasis bits are applied independently of
   greyscale" ([Colour emphasis](https://www.nesdev.org/wiki/Colour_emphasis)). Reason: a mid-frame PPUMASK write
   changes the following pixels only, and the frontend never asks the PPU; one OR per pixel on the hot path. Reading
   the emphasis once per frame in the frontend was discarded.
3. **Input script in YAML**, controller 1 only: `120: [start]` holds the listed buttons from frame 120 until the next
   entry (`125: []` releases them); before the first entry nothing is held. An unknown button name, or a frame that is
   not an integer of at least 1, is an error with a message.
4. **RGB packing: 3 bytes per pixel** (PNG colour type 2; raylib and SDL2 both take RGB24 textures; plan 17 adds RGBA
   if a backend needs it). The packing strategy was chosen by measurement (2026-11-19, a 256 × 240 frame, 60 runs
   after 2 warm-up runs, milliseconds per frame):

   | Strategy | no JIT | YJIT | ZJIT |
   |---|---|---|---|
   | `flat_map` + `pack('C*')` | 13.30 | 11.94 | 12.65 |
   | `values_at` + `join` of a 512-entry table of 3-byte strings | **2.76** | 2.94 | **2.86** |
   | `map` + `join` | 5.36 | 3.63 | 5.25 |
   | preallocated `String` + `<<` | 5.39 | **2.37** | 4.64 |

   `values_at` + `join` is kept: the simplest, and steady under all three; the preallocated `String` wins only under
   YJIT, by 0.6 ms.
5. **`Debug::FrameDump`, its spec and `rake debug:frame` are removed**; the CLI's headless screenshot replaces them,
   and the palette moves to `Frontends::Palette`, which the core never loads.
6. **Headless frames count from 1** (the first `run_frame` after power-up presents frame 1); a frame's digest is the
   SHA-256 of `frame_buffer.pack('S<*')` (9-bit pixels do not fit `C*`).
7. **The CLI is `Ruby::Nes::CommandLine`** in `lib/ruby/nes/command_line.rb` (the plan 10 benchmark's name for the
   same thing; "CLI" would be an acronym outside the glossary). Without `--headless` it stops with a message: the
   windowed frontend arrives in plan 18. It prints the frame count and the last frame's digest.

## Tasks

- [x] `Ppu::FrameTiming` tells `picture_completed` on entering scanline 240.
- [x] `Ppu::Picture`: double buffering (`complete`) and emphasis (`emphasis=`); `Ppu::Renderer` and `Ppu` wiring
      (PPUMASK bits 5-7, the `picture_completed` event).
- [x] Specify and test emphasis RGB conversion (`Frontends::Palette`, 512 colours); measure the packing strategy.
- [x] Specify and test the PNG encoder (signature, chunk CRCs, round trip through `zlib` inflate of IDAT).
- [x] `Frontends::Base` (contract) and `Frontends::Driver` (the loop).
- [x] `Frontends::InputScript` (YAML, held until the next entry, errors).
- [x] Specify and test the headless runner (frame count, screenshot at the right frame, input script applied on the
      right frame, digest stability).
- [x] CLI with `OptionParser`; specify its argument handling.
- [x] A spec that loads the core alone and finds no frontend file loaded.
- [x] Remove `Debug::FrameDump` and `rake debug:frame`; update the nestest golden digest spec if the complete frame
      changes it (after inspecting the PNG).
- [x] `docs/architecture.md` (Rendering, Layout, Frame buffer contract, Hot paths, Decisions log), `docs/GLOSSARY.md`
      (PNG, RGB, CRC; PPM removed); align plans 17, 18 and 25.

## Acceptance criteria

- [x] `exe/ruby-nes spec/fixtures/test_roms/other/nestest.nes --headless --frames 60 --screenshot 60:tmp/out.png`
      writes a PNG that standard viewers open.
- [x] The same run twice yields identical frame digests (determinism), in a spec and from the CLI.
- [x] The core has no dependency on any frontend file (enforced by a spec that loads the core alone).
- [x] A pixel drawn with PPUMASK bits 5-7 set reaches the frame buffer with bits 6-8 set and converts to the colour of
      the matching block.
- [x] The frame handed to the frontend belongs to one frame only (swapped at the post-render scanline).
- [x] 100% branch coverage on frontend code and every touched unit; rubocop clean; `SLOW=1 bundle exec rake` green.

## What was done

- `Ppu::FrameTiming` tells `picture_completed` on entering the post-render scanline; `Ppu::Picture` swaps its two
  buffers there, so `Ppu#frame_buffer` is always one whole frame (no allocation per swap). PPUMASK bits 5-7 reach the
  picture, which ORs them into bits 6-8 of every pixel: pixels are 0-511. The nestest golden digest is unchanged in
  content and now hashes 16-bit pixels.
- `Frontends::Base` (the contract) and `Frontends::Driver` (buttons to the controllers, `run_frame`, `present`);
  `Frontends::Palette` (the 512 colours of `2C02G_U_wiki.pal`, RGB24 with `values_at` + `join`, measured against three
  other strategies); `Frontends::Png` (signature, IHDR, IDAT with filter 0 rows, IEND, CRCs); `Frontends::InputScript`
  (YAML, buttons held until the next entry); `Frontends::Headless` (frames, input, PNG screenshots, a SHA-256 per
  frame).
- `Ruby::Nes::CommandLine` and `CommandLine::Options` behind `exe/ruby-nes ROM --headless [--frames N]
  [--screenshot FRAME:PATH]... [--input SCRIPT]`, with `--help` and `--version`; errors print a message and exit 1.
  `exe/ruby-nes nestest.nes --headless --frames 60 --screenshot 60:tmp/out.png` writes the menu as a PNG, and two runs
  print the same digest. A spec loads the core alone and finds no frontend loaded.
- `Debug::FrameDump` and `rake debug:frame` removed. `docs/architecture.md` (Frontends, Layout, Frame buffer
  contract, decisions 36-39), `docs/GLOSSARY.md` (CRC, PNG, RGB; PPM removed); plans 17, 18 and 25 aligned.
- Independent review: malformed YAML of every kind is an invalid script; frame numbers on the command line are
  decimal; a screenshot past the last frame or a frame asked twice is refused; `--help`/`--version` no longer exit the
  process; the swap stopped allocating; the buffer contract says "valid until the next frame"; smaller cleanups. Not
  applied: dropping the rendering axis from the frame timing spec (the requirement states the event ignores it) and
  making digests optional (plan 25 measures their ~2.4 ms per frame).

## References

- PNG specification — https://www.w3.org/TR/png-3/
- Ruby `Zlib` — https://docs.ruby-lang.org/en/master/Zlib.html
- Ruby `OptionParser` — https://docs.ruby-lang.org/en/master/OptionParser.html
- PPU palettes — https://www.nesdev.org/wiki/PPU_palettes
- Colour emphasis — https://www.nesdev.org/wiki/Colour_emphasis
- PPU registers (PPUMASK) — https://www.nesdev.org/wiki/PPU_registers
- .pal — https://www.nesdev.org/wiki/.pal
- 2C02G_U_wiki.pal — https://www.nesdev.org/wiki/File:2C02G_U_wiki.pal
- pally (the generator's copy of the palette, MIT-0) — https://github.com/Gumball2415/pally
