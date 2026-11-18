# frozen_string_literal: true

module Ruby
  module Nes
    class Cartridge
      Header = Data.define(
        :prg_rom_size,
        :chr_rom_size,
        :mirroring,
        :battery,
        :trainer,
        :alternative_nametables,
        :nes2,
        :mapper_number
      )

      # The 16-byte iNES header, decoded. Only the iNES 1.0 fields (bytes 4-7) are read; NES 2.0 images are recognised
      # but their extended fields are not interpreted. Byte offsets and flags: https://www.nesdev.org/wiki/INES and
      # https://www.nesdev.org/wiki/NES_2.0.
      class Header
        SIZE = 16
        MAGIC = "NES\x1A".bytes.freeze
        PRG_ROM_UNITS_OFFSET = 4
        CHR_ROM_UNITS_OFFSET = 5
        FLAGS_6_OFFSET = 6
        FLAGS_7_OFFSET = 7
        # Rippers may write text such as "DiskDude!" across bytes 7-15; the iNES page's rule of thumb checks the last
        # four, which iNES 1.0 leaves as zero padding.
        PADDING_RANGE = (12..15)

        PRG_ROM_UNIT_SIZE = 16_384
        CHR_ROM_UNIT_SIZE = 8_192
        # "512-byte trainer at $7000-$71FF (stored before PRG data)" (iNES page).
        TRAINER_SIZE = 512
        # The iNES page only says CHR ROM size 0 "means the board uses CHR RAM". 8 KiB is the size emulators assume for
        # iNES 1.0 images, which the NES 2.0 page acknowledges by telling them not to assume it for NES 2.0 headers.
        CHR_RAM_SIZE = 8_192

        # Flags 6.
        VERTICAL_MIRRORING_FLAG = 0b0000_0001
        BATTERY_FLAG = 0b0000_0010
        TRAINER_FLAG = 0b0000_0100
        ALTERNATIVE_NAMETABLES_FLAG = 0b0000_1000

        # Flags 7 bits 3-2 tell the header's format (iNES page, detection procedure): %10 is NES 2.0 and %01 is an
        # archaic iNES header, whose bytes 7-15 cannot be trusted.
        FORMAT_HIGH_BIT = 0b0000_1000
        FORMAT_LOW_BIT = 0b0000_0100

        # Reads the header from the first 16 bytes of an iNES image (a binary String). Raises InvalidImage when the
        # image is shorter than a header or does not start with the magic.
        def self.parse(image)
          header_bytes = image.byteslice(0, SIZE).bytes
          ensure_ines(header_bytes)

          decode(header_bytes)
        end

        def self.ensure_ines(header_bytes)
          if header_bytes.size < SIZE
            raise InvalidImage, "image has #{header_bytes.size} bytes, shorter than the #{SIZE}-byte iNES header"
          end
          return if header_bytes.first(MAGIC.size) == MAGIC

          raise InvalidImage, 'image does not start with the iNES magic "NES" + $1A'
        end
        private_class_method :ensure_ines

        def self.decode(header_bytes)
          flags6 = header_bytes[FLAGS_6_OFFSET]
          flags7 = header_bytes[FLAGS_7_OFFSET]
          nes2 = flags7.allbits?(FORMAT_HIGH_BIT) && flags7.nobits?(FORMAT_LOW_BIT)

          new(
            prg_rom_size: header_bytes[PRG_ROM_UNITS_OFFSET] * PRG_ROM_UNIT_SIZE,
            chr_rom_size: header_bytes[CHR_ROM_UNITS_OFFSET] * CHR_ROM_UNIT_SIZE,
            mirroring: flags6.anybits?(VERTICAL_MIRRORING_FLAG) ? :vertical : :horizontal,
            battery: flags6.anybits?(BATTERY_FLAG),
            trainer: flags6.anybits?(TRAINER_FLAG),
            alternative_nametables: flags6.anybits?(ALTERNATIVE_NAMETABLES_FLAG),
            nes2:,
            mapper_number: mapper_number(flags6, flags7, header_bytes[PADDING_RANGE], nes2:)
          )
        end
        private_class_method :decode

        # Archaic headers: "if the last 4 bytes are not all zero, and the header is not marked for NES 2.0 format, an
        # emulator should either mask off the upper 4 bits of the mapper number or simply refuse to load the ROM" (iNES
        # page), and the same for byte 7 marked archaic. This one masks them, ignoring byte 7's nibble.
        def self.mapper_number(flags6, flags7, padding, nes2:)
          low_half = Bits.high_nibble(flags6)
          return low_half if archaic?(flags7, padding, nes2:)

          Bits.combine_nibbles(low: low_half, high: Bits.high_nibble(flags7))
        end
        private_class_method :mapper_number

        def self.archaic?(flags7, padding, nes2:)
          marked_archaic = flags7.allbits?(FORMAT_LOW_BIT) && flags7.nobits?(FORMAT_HIGH_BIT)

          marked_archaic || (!nes2 && padding.any?(&:nonzero?))
        end
        private_class_method :archaic?

        def battery? = battery
        def trainer? = trainer
        def alternative_nametables? = alternative_nametables
        def nes2? = nes2
        def chr_ram? = chr_rom_size.zero?
        def chr_ram_size = chr_ram? ? CHR_RAM_SIZE : 0
        def trainer_size = trainer? ? TRAINER_SIZE : 0
      end
    end
  end
end
