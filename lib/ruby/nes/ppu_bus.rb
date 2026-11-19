# frozen_string_literal: true

module Ruby
  module Nes
    # The PPU's 14-bit view of its address space (https://www.nesdev.org/wiki/PPU_memory_map): the pattern tables on the
    # cartridge at $0000-$1FFF, reached through the mapper's `ppu_read`/`ppu_write`; the nametables at $2000-$2FFF and
    # their $3000-$3EFF mirror, in VRAM arranged by the mapper's mirroring; and the PPU's palette RAM at $3F00-$3FFF.
    # The PPU hands only 14-bit addresses ($0000-$3FFF).
    class PpuBus
      NAMETABLES_START = 0x2000
      PALETTE_START = 0x3F00
      # The bus is 14 bits wide: a 15-bit v loses its top bit.
      ADDRESS_MASK = 0x3FFF

      def initialize(mapper:)
        @mapper = mapper
        @nametables = Nametables.new(mapper:)
        @palette_ram = PaletteRam.new
      end

      def read(address)
        if address < NAMETABLES_START
          @mapper.ppu_read(address)
        elsif address < PALETTE_START
          @nametables.read(address)
        else
          @palette_ram.read(address)
        end
      end

      def write(address, value)
        if address < NAMETABLES_START
          @mapper.ppu_write(address, value)
        elsif address < PALETTE_START
          @nametables.write(address, value)
        else
          @palette_ram.write(address, value)
        end
      end
    end
  end
end

require_relative 'ppu_bus/palette_ram'
require_relative 'ppu_bus/nametables'
