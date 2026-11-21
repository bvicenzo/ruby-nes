# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # CNROM, iNES mapper 3 (https://www.nesdev.org/wiki/CNROM): "CPU $8000-$FFFF: 32 KiB unbanked PRG-ROM" (16 KiB,
      # mirrored, with the SL solder pad); "PPU $0000-$1FFF: 8 KiB switchable window into 32 KiB CHR-ROM". A write
      # anywhere in $8000-$FFFF selects the CHR bank. "The original CNROM board is always subject to AND-type bus
      # conflicts: the effective value is the value being written bitwise-AND'd with the PRG-ROM content at the address
      # being written to" (plan 19, decision 2). The effective value, wrapped by the CHR size, is the bank; the security
      # diode bits fall outside it ("Emulators need not emulate the functionality of security diodes"). No PRG RAM;
      # mirroring fixed by solder pads (the header's bit). The CHR bank starts at 0 (plan 19, decision 6).
      class Cnrom < Base
        PRG_ROM_SIZES = [16_384, 32_768].freeze

        def initialize(cartridge)
          prg_rom_size = cartridge.prg_rom.size
          unless PRG_ROM_SIZES.include?(prg_rom_size)
            raise InvalidCartridge, "CNROM takes 16 or 32 KiB of PRG ROM, not a PRG ROM of #{prg_rom_size} bytes"
          end

          super
        end

        private

        # The PRG ROM drives the byte at `address` while the CPU writes `value`; the board latches what both agree on.
        def write_register(address, value)
          rom_byte = cpu_read(address, value)
          select_chr_bank(value & rom_byte) # glossary: bitwise-and
        end
      end
    end
  end
end
