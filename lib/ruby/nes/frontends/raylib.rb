# frozen_string_literal: true

require 'raylib'
require_relative 'base'
require_relative 'keyboard'
require_relative 'palette'
require_relative 'raylib_library'

module Ruby
  module Nes
    module Frontends
      # A minimal window on raylib (https://www.raylib.com/cheatsheet/cheatsheet.html) through the raylib-bindings gem,
      # FFI bindings that ship the library built for each platform (plan 17): the frame as a 3× RGB24 texture, the
      # keyboard on the first controller, the audio through a raylib audio stream. No vsync and no pacing (plan 18).
      # The gem's module is `::Raylib`; this class is `Frontends::Raylib`.
      class Raylib < Base
        SCALE = 3
        TITLE = 'ruby-nes'
        # Signed 16-bit mono samples, 44.1 kHz.
        SAMPLE_RATE = 44_100
        SAMPLE_BITS = 16
        CHANNELS = 1
        # The NTSC frame rate, rounded: 60.0988 (https://www.nesdev.org/wiki/Cycle_reference_chart).
        FRAMES_PER_SECOND = 60
        # A frame of audio. A raylib audio stream is two sub-buffers of this many samples, refilled only once played.
        SAMPLES_PER_FRAME = SAMPLE_RATE / FRAMES_PER_SECOND
        # The frame is drawn upright, from one texture level.
        ROTATION = 0.0
        MIPMAP_LEVELS = 1
        KEYS = {
          ::Raylib::KEY_X => :a,
          ::Raylib::KEY_Z => :b,
          ::Raylib::KEY_RIGHT_SHIFT => :select,
          ::Raylib::KEY_ENTER => :start,
          ::Raylib::KEY_UP => :up,
          ::Raylib::KEY_DOWN => :down,
          ::Raylib::KEY_LEFT => :left,
          ::Raylib::KEY_RIGHT => :right
        }.freeze

        # Attaches the raylib library shipped inside the gem's platform build, once per process. raylib-bindings only
        # warns when the library cannot be loaded, so a missing file is a LoadError here, before any call.
        def self.load_library
          return if @library_loaded

          path = RaylibLibrary.path(
            gem_directory: Gem::Specification.find_by_name('raylib-bindings').full_gem_path,
            host_os: RbConfig::CONFIG['host_os'],
            host_cpu: RbConfig::CONFIG['host_cpu']
          )
          raise LoadError, "the raylib library is missing: #{path}" unless File.exist?(path)

          ::Raylib.load_lib(path)
          @library_loaded = true
        end

        def initialize(hidden: false)
          super()
          self.class.load_library
          ::Raylib.SetTraceLogLevel(::Raylib::LOG_WARNING)
          ::Raylib.SetConfigFlags(::Raylib::FLAG_WINDOW_HIDDEN) if hidden
          ::Raylib.InitWindow(Ppu::Picture::WIDTH * SCALE, Ppu::Picture::HEIGHT * SCALE, TITLE)
          @keyboard = Keyboard.new(KEYS)
          open_texture
          open_audio
        end

        def running? = !::Raylib.WindowShouldClose

        def button_states
          [@keyboard.buttons { ::Raylib.IsKeyDown(it) }, 0]
        end

        def present(frame_buffer)
          @pixels.put_bytes(0, Palette.rgb(frame_buffer))
          ::Raylib.UpdateTexture(@texture, @pixels)
          ::Raylib.BeginDrawing
          ::Raylib.DrawTextureEx(@texture, @origin, ROTATION, SCALE.to_f, ::Raylib::WHITE)
          ::Raylib.EndDrawing
        end

        # Refills a sub-buffer that has finished playing; while both are still queued the samples are dropped, as the
        # stream has nowhere to keep them. Up to SAMPLES_PER_FRAME samples are taken.
        def queue_audio(samples)
          return unless ::Raylib.IsAudioStreamProcessed(@stream)

          taken = samples.first(SAMPLES_PER_FRAME)
          @audio_buffer.put_array_of_int16(0, taken)
          ::Raylib.UpdateAudioStream(@stream, @audio_buffer, taken.size)
        end

        def close
          ::Raylib.UnloadAudioStream(@stream)
          ::Raylib.CloseAudioDevice
          ::Raylib.UnloadTexture(@texture)
          ::Raylib.CloseWindow
        end

        private

        def open_texture
          @pixels = FFI::MemoryPointer.new(:uint8, Ppu::Picture::WIDTH * Ppu::Picture::HEIGHT * Palette::BYTES_PER_PIXEL)
          image = ::Raylib::Image.new
          image[:data] = @pixels
          image[:width] = Ppu::Picture::WIDTH
          image[:height] = Ppu::Picture::HEIGHT
          image[:mipmaps] = MIPMAP_LEVELS
          image[:format] = ::Raylib::PIXELFORMAT_UNCOMPRESSED_R8G8B8
          @texture = ::Raylib.LoadTextureFromImage(image)
          @origin = ::Raylib::Vector2.create(0, 0)
        end

        def open_audio
          ::Raylib.SetAudioStreamBufferSizeDefault(SAMPLES_PER_FRAME)
          ::Raylib.InitAudioDevice
          @stream = ::Raylib.LoadAudioStream(SAMPLE_RATE, SAMPLE_BITS, CHANNELS)
          @audio_buffer = FFI::MemoryPointer.new(:int16, SAMPLES_PER_FRAME)
          ::Raylib.PlayAudioStream(@stream)
        end
      end
    end
  end
end
