# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # Opens the raylib window (Frontends::Raylib, plan 17's backend) for CommandLine::Window, loading it only then:
      # its gem is in the optional `frontends` Gemfile group, so a missing library is an Error naming how to install it.
      # A palette shader the graphics driver rejects (plan 32, decision 2) is an Error too.
      module RaylibWindow
        LIBRARY = File.expand_path('../frontends/raylib', __dir__)
        INSTALL_HINT = 'the window needs the optional frontends group: bundle config set --local with frontends'

        # A Frontends::Raylib with the window's keyword arguments (`keys:`, `gamepad_buttons:`, `gamepad_mappings:`,
        # `viewport:`, `jit_name:`, `audio:`, and `hidden:` for the specs); `library` serves the specs too. The gem, or
        # the raylib library file its platform build should ship, may be missing: both are a LoadError.
        def self.call(library: LIBRARY, **window)
          require library
          Frontends::Raylib.new(**window)
        rescue LoadError => error
          raise Error, "#{error.message} (#{INSTALL_HINT})"
        rescue Frontends::RaylibPicture::ShaderError => error
          raise Error, error.message
        end
      end
    end
  end
end
