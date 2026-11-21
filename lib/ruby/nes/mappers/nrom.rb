# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # NROM, iNES mapper 0 (https://www.nesdev.org/wiki/NROM): no registers and no bank switching, so it is the Base
      # board as it comes. PRG ROM is 16 KiB (NROM-128, mirrored at $8000 and $C000) or 32 KiB (NROM-256); CHR is 8 KiB
      # of ROM, or of RAM on homebrew boards; nametable mirroring is fixed by the board (the iNES header's bit). The
      # 8 KiB of PRG RAM at $6000-$7FFF exist on Family BASIC only, but are always present here because test ROMs write
      # their results there (plan 04, decision 2).
      class Nrom < Base
        PRG_ROM_SIZES = [16_384, 32_768].freeze
        CHR_ROM_SIZE = 8_192

        def initialize(cartridge)
          ensure_nrom_sizes(cartridge)
          super(cartridge, prg_ram: true)
        end

        private

        def ensure_nrom_sizes(cartridge)
          prg_rom_size = cartridge.prg_rom.size
          unless PRG_ROM_SIZES.include?(prg_rom_size)
            raise InvalidCartridge, "NROM takes 16 or 32 KiB of PRG ROM, not a PRG ROM of #{prg_rom_size} bytes"
          end

          chr_rom_size = cartridge.chr_rom.size
          return if chr_rom_size.zero? || chr_rom_size == CHR_ROM_SIZE

          raise InvalidCartridge, "NROM takes 8 KiB of CHR ROM or CHR RAM, not a CHR ROM of #{chr_rom_size} bytes"
        end
      end
    end
  end
end
