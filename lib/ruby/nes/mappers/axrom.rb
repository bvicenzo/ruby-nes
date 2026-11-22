# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # AxROM, iNES mapper 7 (https://www.nesdev.org/wiki/AxROM): "CPU $8000-$FFFF: 32 KB switchable PRG ROM bank";
      # "CHR capacity: 8 KB RAM"; "PRG RAM: None". A write anywhere in $8000-$FFFF, laid out `xxxM xPPP`, selects the
      # 32 KiB bank (PPP, wrapped by the PRG ROM size; bit 3 only exists on oversize boards, out of scope) and "1 KB VRAM
      # page for all 4 nametables" (M). The register drives CIRAM A10 ("AxROM latches PRG D4",
      # https://www.nesdev.org/wiki/Mirroring): 0 shows the lower screen, 1 the upper one, a polarity NESdev does not
      # state, taken from Mesen2's AXROM.h (plan 19, decision 7); the header's mirroring is ignored. No bus conflicts:
      # submapper 0 "emulators shouldn't emulate bus conflicts" (decision 2). The register starts at 0 (decision 6).
      class Axrom < Base
        BANK_SIZE = 32_768
        # Bits 2-0: the 32 KiB PRG ROM bank.
        BANK_MASK = 0x07
        # Bit 4: the nametable page.
        SCREEN_FLAG = 0x10

        def initialize(cartridge)
          prg_rom_size = cartridge.prg_rom.size
          # Mappers.build already refused a cartridge without PRG ROM.
          unless (prg_rom_size % BANK_SIZE).zero?
            raise InvalidCartridge, "AxROM takes PRG ROM in 32 KiB banks, not a PRG ROM of #{prg_rom_size} bytes"
          end

          super
          write_register(PRG_ROM_START, 0)
        end

        private

        # The base wraps a bank past the PRG ROM; whole 32 KiB banks keep the two halves of one bank together.
        def write_register(_address, value)
          select_prg_bank(PRG_ROM_START, Bits.low_bits(value, BANK_MASK), PRG_AREA_SIZE)
          @mirroring = (value & SCREEN_FLAG) == 0 ? :single_screen_lower : :single_screen_upper # glossary: flag-clear
        end
      end
    end
  end
end
