# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # NROM, iNES mapper 0 (https://www.nesdev.org/wiki/NROM): no registers and no bank switching. PRG ROM is 16 KiB
      # (NROM-128, mirrored at $8000 and $C000) or 32 KiB (NROM-256); CHR is 8 KiB of ROM, or of RAM on homebrew
      # boards; nametable mirroring is fixed by the board (the iNES header's bit). The 8 KiB of PRG RAM at
      # $6000-$7FFF exist on Family BASIC only, but are always present here because test ROMs write their results
      # there (plan 04, decision 2). Nothing answers $4020-$5FFF.
      class Nrom
        PRG_ROM_SIZES = [16_384, 32_768].freeze
        CHR_SIZE = 8_192
        PRG_RAM_SIZE = 8_192

        PRG_RAM_START = 0x6000
        PRG_ROM_START = 0x8000
        # $6000-$7FFF folds onto the 8 KiB of PRG RAM.
        PRG_RAM_MIRROR_MASK = 0x1FFF

        attr_reader :mirroring

        def initialize(cartridge)
          ensure_nrom_sizes(cartridge)

          @prg_rom = cartridge.prg_rom
          # NROM-128's 16 KiB repeat at $C000; NROM-256's 32 KiB fill $8000-$FFFF. Both sizes are powers of two, so
          # the PRG ROM offset is the address masked by its size minus one ($8000 and $C000 both reach offset 0).
          @prg_rom_mirror_mask = @prg_rom.size - 1
          @prg_ram = Array.new(PRG_RAM_SIZE, 0)
          # No CHR ROM means the board carries its 8 KiB of CHR RAM instead (iNES page: CHR ROM size 0 "means the board
          # uses CHR RAM"). The same array decides it here and in ensure_nrom_sizes.
          @chr_writable = cartridge.chr_rom.empty?
          @chr = @chr_writable ? Array.new(CHR_SIZE, 0) : cartridge.chr_rom
          @mirroring = cartridge.header.mirroring
        end

        # Returns what is left on the CPU data bus: a PRG ROM or PRG RAM byte, or `data_bus` untouched for the
        # unmapped $4020-$5FFF. The CPU bus only hands addresses from $4020.
        def cpu_read(address, data_bus)
          if address >= PRG_ROM_START
            @prg_rom[address & @prg_rom_mirror_mask] # glossary: mirror-down
          elsif address >= PRG_RAM_START
            @prg_ram[address & PRG_RAM_MIRROR_MASK] # glossary: mirror-down
          else
            data_bus
          end
        end

        # Only PRG RAM takes writes: NROM has no registers, and nothing answers $4020-$5FFF.
        def cpu_write(address, value)
          return if address < PRG_RAM_START || address >= PRG_ROM_START

          @prg_ram[address & PRG_RAM_MIRROR_MASK] = value # glossary: mirror-down
        end

        # The PPU bus only hands pattern table addresses, $0000-$1FFF.
        def ppu_read(address) = @chr[address]

        # CHR ROM ignores writes; CHR RAM keeps them.
        def ppu_write(address, value)
          @chr[address] = value if @chr_writable
        end

        # NROM has no IRQ.
        def irq? = false

        private

        def ensure_nrom_sizes(cartridge)
          prg_rom_size = cartridge.prg_rom.size
          unless PRG_ROM_SIZES.include?(prg_rom_size)
            raise InvalidCartridge, "NROM takes 16 or 32 KiB of PRG ROM, not a PRG ROM of #{prg_rom_size} bytes"
          end

          chr_rom_size = cartridge.chr_rom.size
          return if chr_rom_size.zero? || chr_rom_size == CHR_SIZE

          raise InvalidCartridge, "NROM takes 8 KiB of CHR ROM or CHR RAM, not a CHR ROM of #{chr_rom_size} bytes"
        end
      end
    end
  end
end
