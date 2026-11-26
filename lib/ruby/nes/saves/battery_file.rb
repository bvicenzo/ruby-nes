# frozen_string_literal: true

module Ruby
  module Nes
    module Saves
      # A battery save on disk (plan 34): the raw 8 KiB of the cartridge's battery-backed PRG RAM, $6000 first, the
      # format other emulators keep, so a save moves between them. A missing file is no save yet; a file of another
      # size is refused with InvalidSave, so it is never loaded nor overwritten (decision 5). A write is atomic
      # (Saves::AtomicFile, decision 7): a crash mid-write leaves the old save or the new one, never half of one. Off
      # the hot path.
      class BatteryFile
        SIZE = Mappers::Base::PRG_RAM_SIZE
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
          contents = bytes.pack(UNSIGNED_BYTES)
          AtomicFile.write(@path) { it.write(contents) }
        end
      end
    end
  end
end
