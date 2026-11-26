# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

module Ruby
  module Nes
    module Saves
      # Writes a file whole or not at all (plan 34, decision 7; plan 35, decision 7): a temporary file of its own beside
      # the target (a unique name, created exclusively, so two windows of the same game never write into each other's),
      # flushed to the disk, then renamed over the target. A crash mid-write leaves the old file or the new one, never
      # half of one. The folder is created when missing. Off the hot path.
      module AtomicFile
        TEMPORARY_SUFFIX = '.tmp'

        # Yields the temporary file, binary, to write the bytes into; raises what the block or the system raises
        # (SystemCallError). The temporary file is gone afterwards, whether the write succeeded or not.
        def self.write(path)
          folder = File.dirname(path)
          FileUtils.mkdir_p(folder)
          Tempfile.create([File.basename(path), TEMPORARY_SUFFIX], folder, binmode: true) do |temporary_file|
            yield temporary_file
            temporary_file.fsync
            File.rename(temporary_file.path, path)
          end
        end
      end
    end
  end
end
