# 32 — Window presentation

**Depends on:** 31

## Goal

Cut what the windowed frontend spends per frame on presenting the picture, so Super Mario Bros. 3 plays at 60 fps in
the raylib window under YJIT with audio free of crackles, and M7 closes. Emulation, the frame buffer contract and the
`rake bench:frames` digests stay unchanged.

## Context

After plan 31 the emulation alone runs at 61.5 fps under YJIT (16.3 ms a frame, `rake bench:frames`), but the window
showed 50-52 fps while playing world 1-1 (a screen recording at the end of plan 31, 2026-11-23). Measured outside the
window: `Frontends::Palette.rgb`, which turns the 61 440 pixels of a frame into RGB bytes
(`COLOURS.values_at(*frame_buffer).join`), takes about 2.6 ms a frame under YJIT. 16.3 + 2.6 ms is about 18.9 ms, 53
fps: the gap is the presentation, not the emulation. `Frontends::Raylib#present` then copies those bytes into a buffer
(`put_bytes`), uploads the texture and draws it.

## Scope

In, each candidate prototyped and measured (a frame's presentation alone, then the window's frame rate), kept only if
it pays (plan 25, decision 4):

1. **Measure the window's frame** split into emulation, `Palette.rgb`, `put_bytes`, `UpdateTexture` and drawing, and
   the audio pacing's waits, so the cost of each is known before changing any.
2. **The palette lookup off the CPU's Ruby path.** Candidates:
   - upload the frame buffer's pixel values (0-511, 9 bits) packed in C (`pack('S<*')`) as a one-channel 16-bit
     texture and look the colour up in a fragment shader from a 512-entry palette texture;
   - keep the lookup on the CPU but in fewer, larger C operations (a table of the 512 colours packed for the texture's
     format, a single `pack`).
3. **The copy into the texture's buffer**, if step 1 shows it costs: hand raylib the packed string without the extra
   copy.

Out:

- The frame buffer contract (pixels 0-511, plan 16): the headless frontend's digests, the PNG screenshots and the
  benchmarks read it.
- Emulation changes (plans 29-31) and accuracy shortcuts (architecture decision 77).

## Design notes

- Whatever path is kept, the window shows the same colours as today: a spec compares a frame presented through the new
  path with `Palette.rgb` of the same frame buffer.
- The shader path depends on what raylib's Ruby binding exposes (16-bit one-channel textures, shaders, a second texture
  as a sampler); check it in the binding before choosing (open decision 1).
- Hot path rules do not apply to the frontend (once per frame), but no allocation of a frame-sized object per frame is
  the target.

## Open decisions

1. **GPU lookup or CPU packing**: a shader is the largest cut and the most new machinery (shader source, a palette
   texture, the binding's support); CPU packing is smaller and stays in Ruby. Recommendation: measure step 1 first,
   then prototype both.
2. **The SDL3 backend** (plan 17) is not the window's backend; leave it unchanged unless the chosen path is shared.

## Tasks

- [ ] Measure the window's frame by part (step 1).
- [ ] Prototype and measure each candidate; build the kept ones test first.
- [ ] Play world 1-1 in the window under YJIT: the frame rate and the audio.
- [ ] Record in `docs/benchmarks.md` and `docs/architecture.md` (Frontends, decisions log).

## Acceptance criteria

- [ ] The window shows the same colours as before for the same frame buffer.
- [ ] `rake bench:frames` digests unchanged (f0903fbc59bf frame, 10369a5b40df audio).
- [ ] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green.
- [ ] Super Mario Bros. 3 in the raylib window at 60 fps under YJIT with audio free of crackles (M7 closes), or the
      remaining gap quantified per part of the window's frame.

## References

- raylib cheatsheet (textures, shaders) — https://www.raylib.com/cheatsheet/cheatsheet.html
- raylib shaders examples — https://www.raylib.com/examples.html
- Frame buffer contract — `docs/architecture.md`, Frame buffer contract
