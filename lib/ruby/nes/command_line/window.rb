# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # `ruby-nes ROM` without --headless (plan 18): reads and checks the key config before any window opens, names the
      # actions it leaves without a key on the error output, opens the window through `open_window`
      # (CommandLine::RaylibWindow by default), runs the console in it through Frontends::Driver until it stops, and
      # closes it however the run ends. The game's battery save (plan 34) is loaded from `saves_directory` before the
      # window opens, kept in step every few seconds by a Saves::BatteryKeeper the driver tells each frame, and written
      # when the run ends, however it ends, before the window closes. Off the hot path.
      class Window
        # `open_window` takes `keys:` (Frontends::KeyConfig#keys), `viewport:`, `jit_name:` and `audio:` (false with
        # --no-audio) and returns the frontend.
        def initialize(
          open_window: RaylibWindow,
          default_config_path: ConfigFile::DEFAULT_PATH,
          error_output: $stderr,
          saves_directory: Saves::Directory.new
        )
          @open_window = open_window
          @default_config_path = default_config_path
          @error_output = error_output
          @saves_directory = saves_directory
        end

        # Runs the console in the window; raises KeyConfig::InvalidConfig, Saves::InvalidSave, Error or SystemCallError
        # when it cannot.
        def run(console, options, jit_name:)
          config_text = ConfigFile.text(options.config_path, default_path: @default_config_path)
          key_config = Frontends::KeyConfig.parse(config_text)
          warn_unbound(key_config.unbound_actions)
          battery_keeper = Saves::BatteryKeeper
            .for(console:, directory: @saves_directory, rom_path: options.rom_path, error_output: @error_output)
            .tap(&:load)
          frontend = @open_window
            .call(keys: key_config.keys, viewport: viewport(options), jit_name:, audio: options.audio)
          Frontends::Driver.new(console:, frontend:, frame_observer: battery_keeper).run
        ensure
          close(battery_keeper, frontend)
        end

        private

        # The save is written before the window closes, and the window closes even when the save cannot be written. The
        # keeper is there only once its save loaded, so a refused save is never written over.
        def close(battery_keeper, frontend)
          battery_keeper&.close
        ensure
          frontend&.close
        end

        def warn_unbound(actions)
          @error_output.puts("ruby-nes: no key for #{actions.join(', ')}") if actions.any?
        end

        def viewport(options)
          Frontends::Viewport.new(
            scale: options.scale, pixel_aspect: options.pixel_aspect, crop_overscan: options.crop_overscan
          )
        end
      end
    end
  end
end
