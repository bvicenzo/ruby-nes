# 32 — Window presentation

**Status:** done (2026-11-23)

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

## Findings (measured before building, 2026-11-23)

YJIT, a hidden raylib window, Super Mario Bros. 3 world 1-1, 1200 frames after 600 of warm-up, no pacing:

| Part of the window's frame | Today (RGB on the CPU) | Prototype (palette shader) |
|---|---|---|
| Emulation (`run_frame`) | 15.9-18.0 ms | 15.7-16.1 ms |
| `present` | 3.05-3.43 ms | 0.76-0.82 ms |
| `queue_audio` | ~0 | ~0 |
| GC per frame | 0.17-0.19 ms (31 runs) | 0.00 ms (2 runs) |
| Total | 19.0-21.4 ms (47-53 fps) | 16.5-16.9 ms (59-60.6 fps) |

Each piece alone: `Palette.rgb` 2.86 ms; `put_bytes` of its result 0.006 ms; `pack('S<*')` 2.24 ms (no cheaper than
the lookup); `FFI::Pointer#put_array_of_uint16(0, frame_buffer)` 0.35 ms (a C loop, no allocation); the best CPU-only
lookup (an Integer RGBA table, `values_at`, `put_array_of_uint32`) 1.34 ms; `UpdateTexture`, drawing and `EndDrawing`
about 0.4-0.5 ms. The prototype shader, checked on a frame holding all 512 pixel values read back from the screen,
differed from `Palette.rgb` in no pixel.

raylib has no 16-bit integer one-channel texture (`PIXELFORMAT_UNCOMPRESSED_R16` is a half float); a
`PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA` texture takes 2 bytes per pixel, and a pixel stored little-endian puts its low
byte in the grey channel (the shader's `.r`) and its high byte in alpha (`.a`). raylib's default texture filter is
point, so indices are never interpolated, the overscan crop and the 8:7 pixels included. The SDL3 backend was removed
after plan 17 (`bench/frontend_benchmark/backends.rb`), so open decision 2 no longer applies.

## Scope

In:

1. **`Frontends::RaylibPicture`**, the frame on the GPU: a 256×240 index texture (GRAY_ALPHA, each pixel's value
   uploaded with `put_array_of_uint16`), a 512×1 RGB24 palette texture made from `Palette::COLOURS`, and a fragment
   shader that rebuilds the index and reads its colour with `texelFetch`. `draw(frame_buffer, source, destination)`
   and `close`.
2. **`Frontends::Raylib`** draws through it; its RGB texture and `Palette.rgb` call go.
3. The window's frame measured by part before and after, in `docs/benchmarks.md`.

Out:

- The frame buffer contract (pixels 0-511, plan 16): the headless frontend's digests, the PNG screenshots and the
  benchmarks read it; `Palette.rgb` stays for them.
- Emulation changes (plans 29-31) and accuracy shortcuts (architecture decision 77).
- A CPU-only packing path (decision 1).

## Design notes

- The window shows the same colours as before: the picture's spec draws a frame holding all 512 pixel values into a
  render texture and compares it with `Palette.rgb` of the same frame buffer.
- Hot path rules do not apply to the frontend (once per frame), but nothing frame-sized is allocated per frame.

## Decisions

1. **The palette lookup moves to a fragment shader; no CPU-only path is built.** It takes `present` from about 3.2 ms
   to 0.8 ms and the window's GC runs from 31 to 2 per 1200 frames; the best CPU path would leave about 1.8 ms.
2. **A shader that fails to compile or link raises when the window opens**, and `ruby-nes` reports it as an error.
   raylib-bindings ships OpenGL 3.3 builds on every platform it supports; a fallback to the RGB path would keep two
   paths and two specs. raylib swaps a shader that compiles but does not link for its default one, which
   `IsShaderValid` accepts, so the picture also compares the id with the default shader's (found by the review).
3. **A collaborator, `Frontends::RaylibPicture`, owns the textures and the shader.** `Frontends::Raylib` stays a thin
   adapter, and the colours are checked deterministically through a render texture, not by reading the screen after
   the buffers swap (undefined in OpenGL).
4. **The shader source is a heredoc constant** in `RaylibPicture`: no file path to resolve, nothing extra to package.

## Tasks

- [x] Measure the window's frame by part (step 1).
- [x] `Frontends::RaylibPicture`, test first.
- [x] `Frontends::Raylib` draws through it.
- [x] Play world 1-1 in the window under YJIT: the frame rate and the audio.
- [x] Record in `docs/benchmarks.md` and `docs/architecture.md` (Frontends, layout, decisions log).

## Acceptance criteria

- [x] The window shows the same colours as before for the same frame buffer: the picture's spec compares the 512 pixel
      values with `Palette.rgb`.
- [x] `rake bench:frames` digests unchanged (f0903fbc59bf frame, 10369a5b40df audio).
- [x] `SLOW=1 RUBYOPT=--yjit bundle exec rake` green, the window specs running locally (`frontends` group).
- [x] The window's frame measured by part before and after, in `docs/benchmarks.md`.
- [x] Super Mario Bros. 3 in the raylib window at 60 fps under YJIT with audio free of crackles (M7 closes), or the
      remaining gap quantified per part of the window's frame.

## What was done

- **`Frontends::RaylibPicture`**, the frame on the GPU:
  - `put_array_of_uint16` uploads each pixel's value into a grey-and-alpha texture whose filter is set to point;
  - a GLSL 330 fragment shader rebuilds the value and reads its colour with `texelFetch` from a 512×1 texture of
    `Palette::COLOURS`;
  - a shader that does not compile or link raises `ShaderError`, and `CommandLine::RaylibWindow` reports it as an
    `Error`;
  - its spec reads what it draws back from a render texture (`spec/support/raylib_canvas.rb`) and compares the 512
    values, a scaled destination and the overscan crop with `Palette.rgb`.
- **`Frontends::Raylib`** draws through it; its RGB texture and the `Palette.rgb` call are gone.
- **Measured:**
  - `present` fell from about 3.2 ms to 0.8 ms, and the window's GC runs from 31 to 2 per 1200 frames;
  - `rake bench:frontends` YJIT present went from 2.88 to 0.73 ms;
  - `rake bench:frames` digests are unchanged (f0903fbc59bf / 10369a5b40df).
- **Played** (the user, 2026-11-23): Super Mario Bros. 3 world 1-1 in the window under YJIT runs at about 60 fps with
  audio free of crackles, so **M7 closes**.
  - Super Pitfall (UxROM) drops to 48-53 fps in play: its emulation is about 12% heavier than Super Mario Bros. 3's
    (23.2 against 20.7 ms a frame headless, same run conditions).
  - That gap is plan 33's.
- **Review:** the link failure (raylib swaps in its default shader, which `IsShaderValid` accepts) and the uncaught
  `ShaderError` were fixed, with leaves for both; the point filter is now set rather than assumed. Not applied:
  - closing the window when the picture raises (the process exits);
  - sharing the specs' "column plus row" frame buffers (each context states its own premise).

## References

- raylib cheatsheet (textures, shaders) — https://www.raylib.com/cheatsheet/cheatsheet.html
- raylib shaders examples — https://www.raylib.com/examples.html
- raylib's pixel formats and default texture filter — raylib-bindings `lib/raylib_main.rb` (`PIXELFORMAT_*`, `TEXTURE_FILTER_POINT`)
- Frame buffer contract — `docs/architecture.md`, Frame buffer contract
