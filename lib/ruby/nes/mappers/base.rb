# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # The cartridge board every mapper is built on (plan 19, decision 1). The CPU sees PRG ROM through two 16 KiB
      # windows, $8000-$BFFF and $C000-$FFFF, and the PPU sees CHR through one 8 KiB window; a board with registers
      # only turns their writes into window offsets (`write_register`). Out of the box the first window shows the
      # first 16 KiB of PRG ROM and the second the last 16 KiB, which is NROM-128 (both the same 16 KiB), NROM-256
      # and the fixed bank of UxROM (https://www.nesdev.org/wiki/UxROM).
      #
      # PRG RAM at $6000-$7FFF is 8 KiB when the board says it has some (`prg_ram: true`); a board without it does not
      # drive the bus there. Nothing answers $4020-$5FFF. No CHR ROM means 8 KiB of CHR RAM (iNES page: CHR ROM size 0 "means the
      # board uses CHR RAM"). Mirroring is the header's until a board changes it; `irq?` is always false.
      class Base
        PRG_RAM_START = 0x6000
        PRG_ROM_START = 0x8000
        # $6000-$7FFF folds onto the 8 KiB of PRG RAM.
        PRG_RAM_MIRROR_MASK = 0x1FFF
        PRG_WINDOW_SIZE = 16_384
        PRG_RAM_SIZE = 8_192
        # The two PRG ROM windows, as select_prg_bank numbers them.
        FIRST_PRG_WINDOW = 0
        SECOND_PRG_WINDOW = 1
        # Address bit 14 tells the window: $8000-$BFFF is 0, $C000-$FFFF is 1.
        PRG_WINDOW_SELECT_MASK = 0x4000
        PRG_WINDOW_SELECT_SHIFT = 14
        # The address bits within a 16 KiB window.
        PRG_WINDOW_OFFSET_MASK = 0x3FFF
        CHR_WINDOW_SIZE = 8_192
        CHR_RAM_SIZE = 8_192

        attr_reader :mirroring

        def initialize(cartridge, prg_ram: false)
          @prg_rom = cartridge.prg_rom
          @prg_window_offsets = [0, @prg_rom.size - PRG_WINDOW_SIZE]
          @prg_bank_count = @prg_rom.size / PRG_WINDOW_SIZE
          @prg_ram_present = prg_ram
          @prg_ram = prg_ram ? Array.new(PRG_RAM_SIZE, 0) : []
          @chr_writable = cartridge.chr_rom.empty?
          @chr = @chr_writable ? Array.new(CHR_RAM_SIZE, 0) : cartridge.chr_rom
          @chr_bank_offset = 0
          @chr_bank_count = @chr.size / CHR_WINDOW_SIZE
          @mirroring = cartridge.header.mirroring
        end

        # Returns what is left on the CPU data bus: a PRG ROM byte through its window, a PRG RAM byte, or `data_bus`
        # untouched where the board does not drive the bus. The CPU bus only hands addresses from $4020.
        def cpu_read(address, data_bus)
          if address >= PRG_ROM_START
            window = (address & PRG_WINDOW_SELECT_MASK) >> PRG_WINDOW_SELECT_SHIFT # glossary: bit-field
            @prg_rom[@prg_window_offsets[window] + (address & PRG_WINDOW_OFFSET_MASK)] # glossary: low-bits
          elsif address >= PRG_RAM_START && @prg_ram_present
            @prg_ram[address & PRG_RAM_MIRROR_MASK] # glossary: mirror-down
          else
            data_bus
          end
        end

        # $8000-$FFFF goes to the board's registers; $6000-$7FFF to PRG RAM when there is some; the rest is ignored.
        def cpu_write(address, value)
          if address >= PRG_ROM_START
            write_register(address, value)
          elsif address >= PRG_RAM_START && @prg_ram_present
            @prg_ram[address & PRG_RAM_MIRROR_MASK] = value # glossary: mirror-down
          end
        end

        # The PPU bus only hands pattern table addresses, $0000-$1FFF.
        def ppu_read(address) = @chr[@chr_bank_offset + address]

        # CHR ROM ignores writes; CHR RAM keeps them.
        def ppu_write(address, value)
          @chr[@chr_bank_offset + address] = value if @chr_writable
        end

        # No board built here has an IRQ yet (architecture decision 25 replaces this predicate).
        def irq? = false

        private

        # A board without registers ignores writes to $8000-$FFFF.
        def write_register(_address, _value); end

        # Shows the 16 KiB PRG ROM bank `bank` in `window` (FIRST_PRG_WINDOW for $8000-$BFFF, SECOND_PRG_WINDOW for
        # $C000-$FFFF). A bank past the end of PRG ROM wraps around the bank count: a convention (plan 19, decision 5)
        # that matches a board whose ROM lacks the upper address lines when the count is a power of two, as on every
        # licensed board. Called on register writes, off the hot path.
        def select_prg_bank(window, bank)
          @prg_window_offsets[window] = (bank % @prg_bank_count) * PRG_WINDOW_SIZE
        end

        # Shows the 8 KiB CHR bank `bank` at $0000-$1FFF, wrapped around the CHR size as select_prg_bank wraps PRG.
        def select_chr_bank(bank)
          @chr_bank_offset = (bank % @chr_bank_count) * CHR_WINDOW_SIZE
        end
      end
    end
  end
end
