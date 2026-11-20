# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # The text of the window's key config (plan 18, decision 7): the file `--config` names, which must exist, or the
      # default file, which may not, and then the text is empty. Frontends::KeyConfig reads the text. Off the hot path.
      module ConfigFile
        # Expanded only when read, so a process without a home directory reaches it only when it opens a window.
        DEFAULT_PATH = '~/.config/ruby-nes/config.yml'

        # The text of the file at `path`, or of the default file when no path is given; raises SystemCallError when the
        # file given cannot be read.
        def self.text(path, default_path: DEFAULT_PATH)
          return File.read(path) if path

          expanded_path = File.expand_path(default_path)
          return '' unless File.exist?(expanded_path)

          File.read(expanded_path)
        end
      end
    end
  end
end
