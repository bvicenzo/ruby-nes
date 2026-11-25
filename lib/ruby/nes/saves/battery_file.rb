# frozen_string_literal: true

require 'fileutils'
require 'tempfile'

module Ruby
  module Nes
    module Saves
      # A battery save on disk (plan 34): the raw 8 KiB of the cartridge's battery-backed PRG RAM, $6000 first, the
      # format other emulators keep, so a save moves between them. A missing file is no save yet; a file of another
      # size is refused with InvalidSave, so it is never loaded nor overwritten (decision 5). A write goes to a
      # temporary file of its own beside the save (a unique name, created exclusively, so two windows of the same game
      # never write into each other's), flushed to the disk, then renamed over it: a crash mid-write leaves the old
      # save or the new one, never half of one (decision 7). Off the hot path.
      class BatteryFile
        SIZE = Mappers::Base::PRG_RAM_SIZE
        TEMPORARY_SUFFIX = '.tmp'
        UNSIGNED_BYTES = 'C*'

        def initialize(path)
          @path = path
        end

        # The save's bytes, or nil when there is no file; raises InvalidSave for a file of another size and
        # SystemCallError when the file cannot be read.
        def read
          bytes = File.binread(@path).bytes
          return bytes if bytes.size == SIZE

          raise InvalidSave, "#{@path} has #{bytes.size} bytes, but a battery save has #{SIZE}"
        rescue Errno::ENOENT
          nil
        end

        # Writes `bytes` as the save, creating its folder when missing; raises SystemCallError when it cannot. The
        # temporary file is gone afterwards, whether the write succeeded or not.
        def write(bytes)
          folder = File.dirname(@path)
          FileUtils.mkdir_p(folder)
          Tempfile.create([File.basename(@path), TEMPORARY_SUFFIX], folder, binmode: true) do |temporary_file|
            temporary_file.write(bytes.pack(UNSIGNED_BYTES))
            temporary_file.fsync
            File.rename(temporary_file.path, @path)
          end
        end
      end
    end
  end
end
