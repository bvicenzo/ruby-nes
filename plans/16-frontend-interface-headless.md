# 16 — Frontend interface and headless backend

**Depends on:** 13

## Goal

Define the contract between the emulator core and any frontend, and implement the first frontend: headless (no
window, no sound). It lets the graphics library choice be postponed (plan 17) and gives tests and benchmarks a
deterministic runner.

## Context

The core only produces a frame buffer of palette indices (plan 01) and, later, audio samples; it consumes button
states. Converting palette indices to RGB, presenting, pacing and reading the keyboard belong to the frontend.

## Scope

In:

- `Frontends::Base` contract (documented in the class):
  - `present(frame_buffer)` once per frame;
  - `button_states` → bitmasks for both controllers (plan 15: each bitmask goes to `Console#controllers[n].buttons=`,
    bit 0 = A … bit 7 = Right; `Input::Controller::BUTTONS` maps button names to bits);
  - `queue_audio(samples)` (no-op until plan 24);
  - `running?`.
- Shared RGB conversion (palette table moved from plan 13's dumper, `Debug::FrameDump`, NESdev's `2C02G_U_wiki.pal`;
  colour emphasis bits applied here). Plan 13 dumps PPM; the PNG encoder below is new here (plan 13, decision 3).
- A complete frame for the frontend: plan 13 has one frame buffer, filled as the dots run, and `Console#run_frame`
  stops a few dots into the next frame (docs/architecture.md, Frame buffer contract); decide double buffering or a
  copy at a fixed point here.
- `Frontends::Headless`: runs N frames, takes an input script (frame number → buttons), writes PNG screenshots at
  chosen frames, exposes a digest of each frame.
- Minimal PNG encoder in pure Ruby (`zlib` from stdlib; IHDR/IDAT/IEND chunks with CRC).
- CLI first version: `ruby-nes ROM --headless --frames N [--screenshot FRAME:PATH] [--input SCRIPT]`.

Out: windowed frontends (plans 17, 18).

From plan 12: `Console#run_frame` returns when the PPU wraps to (0, 0) (plan 12, decision 7), so the frame buffer is
complete and VBlank has run when the frontend takes it.

## Open decisions

- Input script format: YAML (`120: [start]`) vs a compact text format. Recommendation: YAML, readable in specs.
- RGB packing for frontends: `String` of RGBA bytes (what most libraries take for textures) built via `pack`, vs a
  precomputed 64-entry RGBA string table and `byteslice` copying. Measure in this plan; it is the per-frame cost every
  windowed backend will pay.

## Tasks

- [ ] Specify and test the PNG encoder (signature, chunk CRCs, round trip through `zlib` inflate of IDAT).
- [ ] Specify and test the headless runner (frame count, screenshot at the right frame, input script applied on the
      right frame, digest stability).
- [ ] Specify and test emphasis/greyscale RGB conversion.
- [ ] CLI with `OptionParser`; specify its argument handling.

## Acceptance criteria

- [ ] `exe/ruby-nes spec/fixtures/test_roms/.../nestest.nes --headless --frames 60 --screenshot 60:tmp/out.png`
      writes a PNG that standard viewers open.
- [ ] The same run twice yields identical frame digests (determinism).
- [ ] The core has no dependency on any frontend file (enforced by a spec that loads the core alone).
- [ ] 100% branch coverage on frontend code; rubocop clean.

## References

- PNG specification — https://www.w3.org/TR/png-3/
- Ruby `Zlib` — https://docs.ruby-lang.org/en/master/Zlib.html
- Ruby `OptionParser` — https://docs.ruby-lang.org/en/master/OptionParser.html
- PPU palettes (emphasis) — https://www.nesdev.org/wiki/PPU_palettes
- Colour emphasis — https://www.nesdev.org/wiki/Colour_emphasis
