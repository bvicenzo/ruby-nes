# frozen_string_literal: true

module Ruby
  module Nes
    class Cartridge
      # Reads an iNES image into a Cartridge. The image is laid out as header, trainer (when the header says so),
      # PRG ROM, then CHR ROM (https://www.nesdev.org/wiki/INES). Bytes after the declared sizes (PlayChoice data, a
      # title) are ignored.
      module Loader
        # A missing or unreadable file raises Ruby's own Errno error, which already names the path.
        def self.from_file(path) = from_bytes(File.binread(path))

        # Raises InvalidImage when the bytes are not iNES and TruncatedImage when they are shorter than declared.
        def self.from_bytes(image)
          header = Header.parse(image)
          section_sizes = [header.trainer_size, header.prg_rom_size, header.chr_rom_size]
          ensure_complete(image, Header::SIZE + section_sizes.sum)

          trainer, prg_rom, chr_rom = sections(image, section_sizes)
          Cartridge.new(header:, prg_rom:, chr_rom:, trainer:)
        end

        def self.ensure_complete(image, declared_size)
          return if image.bytesize >= declared_size

          message = "image has #{image.bytesize} bytes, but its header declares #{declared_size} " \
                    '(header, trainer, PRG ROM and CHR ROM)'
          raise TruncatedImage, message
        end
        private_class_method :ensure_complete

        # Cuts consecutive sections of the given sizes, starting right after the header, as frozen arrays of bytes.
        def self.sections(image, sizes)
          offset = Header::SIZE

          sizes.map do |size|
            section = image.byteslice(offset, size).bytes.freeze
            offset += size
            section
          end
        end
        private_class_method :sections
      end
    end
  end
end
