# frozen_string_literal: true

require 'raylib'
require_relative '../audio'
require_relative 'audio_pacing'
require_relative 'base'
require_relative 'controls'
require_relative 'frame_pacing'
require_relative 'frame_rate'
require_relative 'gamepad'
require_relative 'hotkeys'
require_relative 'key_bindings'
require_relative 'key_config'
require_relative 'notice'
require_relative 'players'
require_relative 'raylib_audio_stream'
require_relative 'raylib_input'
require_relative 'raylib_library'
require_relative 'raylib_picture'
require_relative 'viewport'

module Ruby
  module Nes
    module Frontends
      # The emulator's window on raylib (https://www.raylib.com/cheatsheet/cheatsheet.html) through the raylib-bindings
      # gem, FFI bindings that ship the library built for each platform (plan 17). An adapter: the decisions live in its
      # collaborators, each specified on its own (plan 18). The frame is drawn by Frontends::RaylibPicture, its colours
      # looked up on the GPU (plan 32), into the Frontends::Viewport; the keyboard and the gamepads (plan 36), read
      # through Frontends::RaylibInput, drive the controllers through Frontends::Players, and the keyboard drives the
      # emulator through Frontends::Hotkeys; the frame rate (Frontends::FrameRate) and the JIT are drawn over the frame
      # while the overlay is shown, and a message (Frontends::Notice, plan 35) at the bottom left while it lasts; after
      # each frame the pacing waits. With audio (plan 24), each frame's samples go through Frontends::AudioPacing into a
      # raylib audio stream (Frontends::RaylibAudioStream), and the audio paces the window; while paused it queues
      # silence, and after a save state is loaded it drops what it queued. Without audio, or when no audio device opens,
      # the timer paces it (Frontends::FramePacing). A pacing given replaces either, the audio still being fed (the
      # benchmark's tone runs unpaced). The gem's module is `::Raylib`; this class is `Frontends::Raylib`.
      class Raylib < Base
        TITLE = 'ruby-nes'
        # Signed 16-bit mono samples at the core's rate, 48 kHz (plan 24, decision 1).
        SAMPLE_RATE = Audio::SAMPLE_RATE
        # The NTSC frame rate, rounded: 60.0988 (https://www.nesdev.org/wiki/Cycle_reference_chart).
        FRAMES_PER_SECOND = 60
        # A frame of audio, 800 samples. A raylib audio stream is two sub-buffers of this many samples, refilled only
        # once played. Frontends::AudioDeviceLatency's latency is chosen to fit in one: revisit it if this changes.
        SAMPLES_PER_FRAME = SAMPLE_RATE / FRAMES_PER_SECOND
        # The overlay's text, at the top left corner of the window, and the message's, at the bottom left, in screen
        # pixels.
        OVERLAY_MARGIN = 8
        OVERLAY_FONT_SIZE = 20
        KEY_PREFIX = 'KEY_'
        GAMEPAD_BUTTON_PREFIX = 'GAMEPAD_BUTTON_'
        # KEY_NULL is "no key pressed", not a key; GAMEPAD_BUTTON_UNKNOWN is raylib's "for error checking", not a
        # button.
        NOT_INPUTS = %i[KEY_NULL GAMEPAD_BUTTON_UNKNOWN].freeze

        # raylib's constants of one kind of input to their codes, named as a config file writes them: lower case,
        # without the prefix (`right_shift`, `right_face_right`).
        def self.input_codes(prefix)
          (::Raylib.constants.grep(/\A#{prefix}/) - NOT_INPUTS)
            .to_h { [it.name.delete_prefix(prefix).downcase, ::Raylib.const_get(it)] }
            .freeze
        end
        private_class_method :input_codes

        # raylib's key names to its key codes, the names a config file uses (plan 18, decision 7).
        KEY_CODES = input_codes(KEY_PREFIX)
        # raylib's gamepad button names to their codes, the names the config file's `gamepad:` section uses (plan 36).
        GAMEPAD_BUTTON_CODES = input_codes(GAMEPAD_BUTTON_PREFIX)
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

        # `keys` maps actions to key names and `gamepad_buttons` controller buttons to gamepad button names
        # (Frontends::KeyConfig); `gamepad_mappings`, SDL GameControllerDB lines for pads raylib does not know, are
        # handed to raylib, which skips the lines it cannot read without saying so. `jit_name` is shown in the overlay.
        # The pacing is the audio's with `audio` and an audio device, the timer's otherwise, unless one is given.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(
          keys: KeyConfig::DEFAULTS,
          gamepad_buttons: KeyConfig::GAMEPAD_DEFAULTS,
          gamepad_mappings: nil,
          viewport: DEFAULT_VIEWPORT,
          jit_name: 'none',
          audio: true,
          pacing: nil,
          hidden: false
        )
          super()
          self.class.load_library
          key_bindings = KeyBindings.new(keys, codes: KEY_CODES, kind: 'key')
          @players = players(key_bindings, gamepad_buttons)
          @hotkeys = Hotkeys.new(key_bindings.hotkeys)
          @jit_name = jit_name
          @notice = Notice.new
          @notice_top = viewport.height - OVERLAY_MARGIN - OVERLAY_FONT_SIZE
          open_window(viewport, hidden)
          ::Raylib.SetGamepadMappings(gamepad_mappings) if gamepad_mappings
          @picture = RaylibPicture.new
          place_picture(viewport)
          open_audio if audio
          @pacing = pacing || @audio_pacing || FramePacing.new
          # Measured from here, so the first rate shown leaves out the time the window and the audio took to open.
          @frame_rate = FrameRate.new
        end

        def running? = !::Raylib.WindowShouldClose && !@hotkeys.quit?

        def paused? = @hotkeys.paused?

        def reset_requested? = @hotkeys.reset_requested?

        def button_states = @players.button_states(RaylibInput)

        def state_action = @hotkeys.state_action

        # Shows `message` over the picture for Notice::FRAMES_SHOWN frames.
        def notify(message)
          @notice.show(message)
        end

        def discard_audio
          @audio_pacing&.clear
        end

        # Draws the frame (and the overlay), reads the hotkeys pressed meanwhile (raylib polls its input events as the
        # drawing ends), counts the frame, queues a frame of silence while paused and waits for the pacing.
        def present(frame_buffer)
          ::Raylib.BeginDrawing
          @picture.draw(frame_buffer, @source, @destination)
          draw_overlay if @hotkeys.frame_rate_shown?
          draw_notice
          ::Raylib.EndDrawing
          @hotkeys.poll { ::Raylib.IsKeyPressed(it) }
          @frame_rate.tick
          @notice.tick
          @audio_pacing.queue_silence if @audio_pacing && paused?
          @pacing.wait
        end

        # Queues the frame's samples for the audio pacing to submit; ignored without audio.
        def queue_audio(samples)
          @audio_pacing&.queue(samples)
        end

        def close
          @audio_stream&.close
          @picture.close
          ::Raylib.CloseWindow
        end

        private

        def players(key_bindings, gamepad_buttons)
          gamepad_bindings = KeyBindings.new(gamepad_buttons, codes: GAMEPAD_BUTTON_CODES, kind: 'gamepad button')
          Players.new(
            keyboard: Controls.new(key_bindings.controller),
            gamepad: Gamepad.new(Controls.new(gamepad_bindings.controller))
          )
        end

        # Esc quits through the hotkeys, so raylib's own exit key ("default is ESC") is turned off.
        def open_window(viewport, hidden)
          ::Raylib.SetTraceLogLevel(::Raylib::LOG_WARNING)
          ::Raylib.SetConfigFlags(::Raylib::FLAG_WINDOW_HIDDEN) if hidden
          ::Raylib.InitWindow(viewport.width, viewport.height, TITLE)
          ::Raylib.SetExitKey(::Raylib::KEY_NULL)
        end

        # The part of the frame drawn, and where: the whole window.
        def place_picture(viewport)
          source = viewport.source
          @source = ::Raylib::Rectangle.create(source.x, source.y, source.width, source.height)
          @destination = ::Raylib::Rectangle.create(0, 0, viewport.width, viewport.height)
        end

        # Without a usable output device the window runs silent, paced by the timer.
        def open_audio
          stream = RaylibAudioStream.new(sample_rate: SAMPLE_RATE, chunk_size: SAMPLES_PER_FRAME)
          return stream.close unless stream.ready?

          @audio_stream = stream
          @audio_pacing = AudioPacing.new(stream:, chunk_size: SAMPLES_PER_FRAME)
        end

        def draw_overlay
          text = "#{@frame_rate} | #{@jit_name}"
          ::Raylib.DrawText(text, OVERLAY_MARGIN, OVERLAY_MARGIN, OVERLAY_FONT_SIZE, ::Raylib::GREEN)
        end

        def draw_notice
          text = @notice.text
          ::Raylib.DrawText(text, OVERLAY_MARGIN, @notice_top, OVERLAY_FONT_SIZE, ::Raylib::YELLOW) if text
        end
      end
    end
  end
end
