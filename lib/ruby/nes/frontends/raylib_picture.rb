# frozen_string_literal: true

require 'ffi'
require 'raylib'
require_relative '../ppu/picture'
require_relative 'palette'

module Ruby
  module Nes
    module Frontends
      # The frame on the GPU, a collaborator of Frontends::Raylib (plan 32): each pixel's value (0-511,
      # docs/architecture.md Frame buffer contract) is uploaded as is and a fragment shader looks its colour up in a
      # texture of Frontends::Palette's 512 colours, so the window shows the colours Frontends::Palette.rgb gives the
      # same frame, with no RGB conversion on the CPU (plan 32, decision 1). raylib has no 16-bit integer one-channel
      # texture, so the pixels go into a grey-and-alpha texture of 2 bytes per pixel: a value stored in the machine's
      # byte order, little-endian on every platform raylib-bindings ships, puts its low byte in grey (the shader's red)
      # and its high byte in alpha. The texture's filter is set to point, so values are never interpolated, whatever
      # the scale. A value past 511 is outside the contract and not checked (its colour is undefined). Opened once a
      # window is (it needs the graphics context); a shader that does not compile or link raises (plan 32, decision 2).
      class RaylibPicture
        # Raised when the fragment shader does not compile or link; raylib's log says why.
        class ShaderError < StandardError; end

        # The pixel's value rebuilt from its two bytes, each a channel normalised to 0-1, and its colour read by integer
        # coordinate from the palette texture. `fragTexCoord`, `texture0` and `finalColor` are the names raylib's
        # default vertex shader and drawing functions use.
        FRAGMENT_SHADER = <<~GLSL
          #version 330
          in vec2 fragTexCoord;
          uniform sampler2D texture0;
          uniform sampler2D palette;
          out vec4 finalColor;
          const float CHANNEL_MAXIMUM = 255.0;
          const int HIGH_BYTE_WEIGHT = 256;
          void main() {
            vec4 pixel = texture(texture0, fragTexCoord);
            int low_byte = int(round(pixel.r * CHANNEL_MAXIMUM));
            int high_byte = int(round(pixel.a * CHANNEL_MAXIMUM));
            int pixel_value = low_byte + high_byte * HIGH_BYTE_WEIGHT;
            finalColor = vec4(texelFetch(palette, ivec2(pixel_value, 0), 0).rgb, 1.0);
          }
        GLSL
        PALETTE_SAMPLER = 'palette'
        # The pixels' values, 2 bytes each, and the palette's colours.
        INDEX_FORMAT = ::Raylib::PIXELFORMAT_UNCOMPRESSED_GRAY_ALPHA
        PALETTE_FORMAT = ::Raylib::PIXELFORMAT_UNCOMPRESSED_R8G8B8
        PIXELS = Ppu::Picture::WIDTH * Ppu::Picture::HEIGHT
        # One texture level; drawn upright.
        MIPMAP_LEVELS = 1
        ROTATION = 0.0
        ORIGIN = ::Raylib::Vector2.create(0, 0)

        def initialize(fragment_shader: FRAGMENT_SHADER)
          @shader = ::Raylib.LoadShaderFromMemory(nil, fragment_shader)
          raise ShaderError, 'the palette shader did not compile or link' unless loaded?(@shader)

          @palette_location = ::Raylib.GetShaderLocation(@shader, PALETTE_SAMPLER)
          @pixels = FFI::MemoryPointer.new(:uint16, PIXELS)
          @frame = load_texture(@pixels, Ppu::Picture::WIDTH, Ppu::Picture::HEIGHT, INDEX_FORMAT)
          ::Raylib.SetTextureFilter(@frame, ::Raylib::TEXTURE_FILTER_POINT)
          @palette = load_palette
        end

        # Draws the part of the frame `source` selects into `destination` (raylib Rectangles), between BeginDrawing and
        # EndDrawing. Nothing frame-sized is allocated: the values are copied into the same memory each frame.
        def draw(frame_buffer, source, destination)
          @pixels.put_array_of_uint16(0, frame_buffer)
          ::Raylib.UpdateTexture(@frame, @pixels)
          ::Raylib.BeginShaderMode(@shader)
          ::Raylib.SetShaderValueTexture(@shader, @palette_location, @palette)
          ::Raylib.DrawTexturePro(@frame, source, destination, ORIGIN, ROTATION, ::Raylib::WHITE)
          ::Raylib.EndShaderMode
        end

        def close
          ::Raylib.UnloadTexture(@palette)
          ::Raylib.UnloadTexture(@frame)
          ::Raylib.UnloadShader(@shader)
        end

        private

        # A shader that does not compile is not valid; one that compiles but does not link is replaced by raylib's
        # default shader ("using default shader" in its log).
        def loaded?(shader) = ::Raylib.IsShaderValid(shader) && shader[:id] != ::Raylib.rlGetShaderIdDefault

        # The 512 colours in a row, RGB24, pixel value n at column n.
        def load_palette
          colours = Palette::COLOURS.join
          memory = FFI::MemoryPointer.new(:uint8, colours.bytesize)
          memory.put_bytes(0, colours)
          load_texture(memory, Palette::COLOURS.size, 1, PALETTE_FORMAT)
        end

        def load_texture(data, width, height, format)
          image = ::Raylib::Image.new
          image[:data] = data
          image[:width] = width
          image[:height] = height
          image[:mipmaps] = MIPMAP_LEVELS
          image[:format] = format
          ::Raylib.LoadTextureFromImage(image)
        end
      end
    end
  end
end
