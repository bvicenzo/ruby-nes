# frozen_string_literal: true

require 'raylib'
require_relative 'base'
require_relative 'frame_pacing'
require_relative 'frame_rate'
require_relative 'hotkeys'
require_relative 'key_bindings'
require_relative 'key_config'
require_relative 'keyboard'
require_relative 'opposite_directions'
require_relative 'palette'
require_relative 'raylib_library'
require_relative 'viewport'

module Ruby
  module Nes
    module Frontends
      # The emulator's window on raylib (https://www.raylib.com/cheatsheet/cheatsheet.html) through the raylib-bindings
      # gem, FFI bindings that ship the library built for each platform (plan 17). An adapter: the decisions live in
      # its collaborators, each specified on its own (plan 18). The frame is drawn as an RGB24 texture into the
      # Frontends::Viewport; the keyboard drives the first controller through Frontends::Keyboard with opposite
      # directions cancelled (Frontends::OppositeDirections) and the emulator through Frontends::Hotkeys; the frame rate
      # (Frontends::FrameRate) and the JIT are drawn over the frame while the overlay is shown; after each frame the
      # pacing waits (Frontends::FramePacing, or any object answering `wait`); the audio goes through a raylib audio
      # stream. The gem's module is `::Raylib`; this class is `Frontends::Raylib`.
      class Raylib < Base
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
        # The overlay's text, at the top left corner of the window, in screen pixels.
        OVERLAY_MARGIN = 8
        OVERLAY_FONT_SIZE = 20
        KEY_PREFIX = 'KEY_'
        # KEY_NULL is "no key pressed", not a key.
        NOT_A_KEY = :KEY_NULL

        # A raylib key constant's name as a config file writes it: lower case, without the prefix (`right_shift`).
        def self.key_name(constant) = constant.name.delete_prefix(KEY_PREFIX).downcase
        private_class_method :key_name

        # raylib's key names to its key codes, the names a config file uses (plan 18, decision 7).
        KEY_CODES = (::Raylib.constants.grep(/\A#{KEY_PREFIX}/o) - [NOT_A_KEY])
          .to_h { [key_name(it), ::Raylib.const_get(it)] }
          .freeze
        DEFAULT_VIEWPORT = Viewport.new(scale: 3, pixel_aspect: 1, crop_overscan: false)

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

        # `keys` maps actions to key names (Frontends::KeyConfig#keys); `jit_name` is shown in the overlay.
        def initialize(
          keys: KeyConfig.new({}).keys,
          viewport: DEFAULT_VIEWPORT,
          jit_name: 'none',
          pacing: FramePacing.new,
          hidden: false
        )
          super()
          self.class.load_library
          key_bindings = KeyBindings.new(keys, key_codes: KEY_CODES)
          @keyboard = Keyboard.new(key_bindings.controller)
          @hotkeys = Hotkeys.new(key_bindings.hotkeys)
          @jit_name = jit_name
          @pacing = pacing
          open_window(viewport, hidden)
          open_texture
          place_texture(viewport)
          open_audio
          # Measured from here, so the first rate shown leaves out the time the window and the audio took to open.
          @frame_rate = FrameRate.new
        end

        def running? = !::Raylib.WindowShouldClose && !@hotkeys.quit?

        def paused? = @hotkeys.paused?

        def reset_requested? = @hotkeys.reset_requested?

        def button_states
          [OppositeDirections.filter(@keyboard.buttons { ::Raylib.IsKeyDown(it) }), 0]
        end

        # Draws the frame (and the overlay), reads the hotkeys pressed meanwhile (raylib polls its input events as the
        # drawing ends), counts the frame and waits for the pacing.
        def present(frame_buffer)
          @pixels.put_bytes(0, Palette.rgb(frame_buffer))
          ::Raylib.UpdateTexture(@texture, @pixels)
          ::Raylib.BeginDrawing
          ::Raylib.DrawTexturePro(@texture, @source, @destination, @origin, ROTATION, ::Raylib::WHITE)
          draw_overlay if @hotkeys.frame_rate_shown?
          ::Raylib.EndDrawing
          @hotkeys.poll { ::Raylib.IsKeyPressed(it) }
          @frame_rate.tick
          @pacing.wait
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

        # Esc quits through the hotkeys, so raylib's own exit key ("default is ESC") is turned off.
        def open_window(viewport, hidden)
          ::Raylib.SetTraceLogLevel(::Raylib::LOG_WARNING)
          ::Raylib.SetConfigFlags(::Raylib::FLAG_WINDOW_HIDDEN) if hidden
          ::Raylib.InitWindow(viewport.width, viewport.height, TITLE)
          ::Raylib.SetExitKey(::Raylib::KEY_NULL)
        end

        def open_texture
          @pixels = FFI::MemoryPointer.new(:uint8, Ppu::Picture::WIDTH * Ppu::Picture::HEIGHT * Palette::BYTES_PER_PIXEL)
          image = ::Raylib::Image.new
          image[:data] = @pixels
          image[:width] = Ppu::Picture::WIDTH
          image[:height] = Ppu::Picture::HEIGHT
          image[:mipmaps] = MIPMAP_LEVELS
          image[:format] = ::Raylib::PIXELFORMAT_UNCOMPRESSED_R8G8B8
          @texture = ::Raylib.LoadTextureFromImage(image)
        end

        # The part of the frame drawn, and where: the whole window.
        def place_texture(viewport)
          source = viewport.source
          @source = ::Raylib::Rectangle.create(source.x, source.y, source.width, source.height)
          @destination = ::Raylib::Rectangle.create(0, 0, viewport.width, viewport.height)
          @origin = ::Raylib::Vector2.create(0, 0)
        end

        def open_audio
          ::Raylib.SetAudioStreamBufferSizeDefault(SAMPLES_PER_FRAME)
          ::Raylib.InitAudioDevice
          @stream = ::Raylib.LoadAudioStream(SAMPLE_RATE, SAMPLE_BITS, CHANNELS)
          @audio_buffer = FFI::MemoryPointer.new(:int16, SAMPLES_PER_FRAME)
          ::Raylib.PlayAudioStream(@stream)
        end

        def draw_overlay
          text = "#{@frame_rate} | #{@jit_name}"
          ::Raylib.DrawText(text, OVERLAY_MARGIN, OVERLAY_MARGIN, OVERLAY_FONT_SIZE, ::Raylib::GREEN)
        end
      end
    end
  end
end
