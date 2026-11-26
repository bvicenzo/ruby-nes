# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # The ROM browser's cached previews (plan 37, decision 2): a game's preview state (Saves::ConsoleState's bytes)
        # at Saves::Directory#preview_path, by the ROM's SHA-256, written atomically (Saves::AtomicFile). A cache: a
        # preview that cannot be read is as one never made, and one that cannot be written is made again next time,
        # each with a warning on the error output; neither stops the menu. Off the hot path: once per game in focus.
        class PreviewCache
          # `directory` is a Saves::Directory; warnings go to `error_output`.
          def initialize(directory:, error_output:)
            @directory = directory
            @error_output = error_output
          end

          # The preview's bytes for the ROM whose SHA-256 is `rom_digest`, or nil.
          def read(rom_digest)
            File.binread(@directory.preview_path(rom_digest))
          rescue Errno::ENOENT
            nil
          rescue Saves::Error, SystemCallError => error
            @error_output.puts("ruby-nes: the preview cannot be read: #{error.message}")
            nil
          end

          def write(rom_digest, bytes)
            Saves::AtomicFile.write(@directory.preview_path(rom_digest)) { it.write(bytes) }
          rescue Saves::Error, SystemCallError => error
            @error_output.puts("ruby-nes: the preview was not saved: #{error.message}")
          end
        end
      end
    end
  end
end
