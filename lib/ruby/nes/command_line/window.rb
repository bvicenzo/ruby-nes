# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # `ruby-nes ROM` without --headless (plan 18): reads and checks the key config before any window opens, names the
      # actions it leaves without a key on the error output, opens the window through `open_window`
      # (CommandLine::RaylibWindow by default), runs the console in it through Frontends::Driver until it stops, and
      # closes it however the run ends. Off the hot path.
      class Window
        # `open_window` takes `keys:` (Frontends::KeyConfig#keys), `viewport:` and `jit_name:` and returns the frontend.
        def initialize(open_window: RaylibWindow, default_config_path: ConfigFile::DEFAULT_PATH, error_output: $stderr)
          @open_window = open_window
          @default_config_path = default_config_path
          @error_output = error_output
        end

        # Runs the console in the window; raises KeyConfig::InvalidConfig, Error or SystemCallError when it cannot.
        def run(console, options, jit_name:)
          config_text = ConfigFile.text(options.config_path, default_path: @default_config_path)
          key_config = Frontends::KeyConfig.parse(config_text)
          warn_unbound(key_config.unbound_actions)
          frontend = @open_window.call(keys: key_config.keys, viewport: viewport(options), jit_name:)
          Frontends::Driver.new(console:, frontend:).run
        ensure
          frontend&.close
        end

        private

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
