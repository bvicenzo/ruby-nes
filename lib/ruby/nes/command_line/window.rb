# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # The window of `ruby-nes` without --headless (plan 18): reads and checks the key config before any window opens,
      # names the actions it leaves without a key on the error output, opens the window through `open_window`
      # (CommandLine::RaylibWindow by default) and closes it however its run ends.
      #
      # - `run`, for `ruby-nes ROM`, plays one game in it (CommandLine::Game): the game's battery save (plan 34) is
      #   loaded from `saves_directory` before the window opens, so a refused save opens no window, and written when the
      #   game is closed, before the window closes.
      # - `browse`, for `ruby-nes [FOLDER]`, opens the ROM browser in it (plan 37, CommandLine::Browser) on the ROMs of
      #   the folder the command line names, else the config's `roms_directory:`, else ROMS_FOLDER under the current
      #   directory (decision 1), listed (Frontends::Browser::RomList) before the window opens.
      #
      # Off the hot path.
      class Window
        ROMS_FOLDER = 'roms'

        # `open_window` takes `keys:`, `gamepad_buttons:` and `gamepad_mappings:` (Frontends::KeyConfig), `viewport:`,
        # `jit_name:` and `audio:` (false with --no-audio) and returns the frontend.
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
          key_config = read_key_config(options)
          game = Game.new(console:, rom_path: options.path, directory: @saves_directory, error_output: @error_output)
          game.load
          frontend = open_frontend(key_config, options, jit_name)
          game.play(frontend)
        ensure
          close(game, frontend)
        end

        # Browses the ROMs of the folder in the window; raises KeyConfig::InvalidConfig, Error or SystemCallError when
        # it cannot.
        def browse(options, jit_name:)
          key_config = read_key_config(options)
          folder = roms_folder(options.path || key_config.roms_directory || ROMS_FOLDER)
          roms = Frontends::Browser::RomList.scan(folder, directory: @saves_directory)
          frontend = open_frontend(key_config, options, jit_name)
          browser(frontend, folder, roms, options).run
        ensure
          frontend&.close
        end

        private

        def read_key_config(options)
          config_text = ConfigFile.text(options.config_path, default_path: @default_config_path)
          Frontends::KeyConfig.parse(config_text).tap { warn_unbound(it.unbound_actions) }
        end

        # The folder at `path`, its `~` expanded; raises KeyConfig::InvalidConfig when it names a user with no home.
        def roms_folder(path)
          File.expand_path(path)
        rescue ArgumentError => error
          raise Frontends::KeyConfig::InvalidConfig, "#{Frontends::KeyConfig::ROMS_DIRECTORY}: #{error.message}"
        end

        def browser(frontend, folder, roms, options)
          Browser.new(
            frontend:,
            folder:,
            roms:,
            directory: @saves_directory,
            audio_sample_rate: options.audio_sample_rate,
            error_output: @error_output
          )
        end

        def open_frontend(key_config, options, jit_name)
          @open_window.call(
            keys: key_config.keys,
            gamepad_buttons: key_config.gamepad_buttons,
            gamepad_mappings: key_config.gamepad_mappings,
            viewport: viewport(options),
            jit_name:,
            audio: options.audio
          )
        end

        # The save is written before the window closes, and the window closes even when the save cannot be written.
        def close(game, frontend)
          game&.close
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
