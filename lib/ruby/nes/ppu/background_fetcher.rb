# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The background's four memory fetches of each tile (https://www.nesdev.org/wiki/PPU_rendering): "Nametable
      # byte", "Attribute table byte", "Pattern table tile low" and "Pattern table tile high (8 bytes above pattern
      # table tile low address)", each kept in a latch until the shift registers take them. The addresses come from v
      # (https://www.nesdev.org/wiki/PPU_scrolling, "Tile and attribute fetching") and, for the patterns, from the
      # background pattern table PPUCTRL bit 4 selects, told by the Ppu; a pattern address is "0HNNNN NNNNPyyy", half,
      # tile number, bit plane and fine Y (https://www.nesdev.org/wiki/PPU_pattern_tables). An attribute byte holds
      # one palette per 2×2-tile quadrant, "(bottomright << 6) | (bottomleft << 4) | (topright << 2) | (topleft << 0)"
      # (https://www.nesdev.org/wiki/PPU_attribute_tables); coarse X bit 1 and coarse Y bit 1 pick the quadrant, a
      # derivation from the attribute address layout (plan 13). Hot path: one fetch every 2 dots while rendering.
      class BackgroundFetcher
        # "tile address = 0x2000 | (v & 0x0FFF)".
        TILE_ADDRESS_BASE = 0x2000
        TILE_ADDRESS_MASK = 0x0FFF
        # "attribute address = 0x23C0 | (v & 0x0C00) | ((v >> 4) & 0x38) | ((v >> 2) & 0x07)": the nametable, the high
        # 3 bits of coarse Y and the high 3 bits of coarse X.
        ATTRIBUTE_ADDRESS_BASE = 0x23C0
        ATTRIBUTE_NAMETABLE_MASK = ScrollRegisters::NAMETABLE_SELECT_MASK
        ATTRIBUTE_ROW_SHIFT = 4
        ATTRIBUTE_ROW_MASK = 0x38
        ATTRIBUTE_COLUMN_SHIFT = 2
        ATTRIBUTE_COLUMN_MASK = 0x07
        # The quadrant's shift in the attribute byte (0, 2, 4 or 6): coarse X bit 1 (v bit 1) adds 2, coarse Y bit 1
        # (v bit 6, moved to bit 2) adds 4.
        QUADRANT_COLUMN_MASK = 0x02
        QUADRANT_ROW_SHIFT = 4
        QUADRANT_ROW_MASK = 0x04
        PALETTE_MASK = 0x03
        # A tile is 16 bytes, plane 0 then plane 1 ("P: Bit plane"); fine Y picks the row.
        TILE_SIZE_SHIFT = 4
        HIGH_PLANE_OFFSET = 8

        attr_reader :tile, :palette, :pattern_low, :pattern_high
        # The background pattern table's base address, $0000 or $1000.
        attr_writer :pattern_table

        def initialize(bus:, scroll_registers:, pattern_table: 0)
          @bus = bus
          @scroll_registers = scroll_registers
          @pattern_table = pattern_table
          @tile = 0
          @palette = 0
          @pattern_low = 0
          @pattern_high = 0
        end

        def fetch_nametable_byte
          tile_offset = @scroll_registers.vram_address & TILE_ADDRESS_MASK # glossary: low-bits
          @tile = @bus.read(TILE_ADDRESS_BASE | tile_offset) # glossary: bitwise-or
        end

        def fetch_attribute
          vram_address = @scroll_registers.vram_address
          nametable = vram_address & ATTRIBUTE_NAMETABLE_MASK # glossary: bitwise-and
          row = (vram_address >> ATTRIBUTE_ROW_SHIFT) & ATTRIBUTE_ROW_MASK # glossary: bit-field
          column = (vram_address >> ATTRIBUTE_COLUMN_SHIFT) & ATTRIBUTE_COLUMN_MASK # glossary: bit-field
          attribute = @bus.read(ATTRIBUTE_ADDRESS_BASE | nametable | row | column) # glossary: bitwise-or
          quadrant_row = (vram_address >> QUADRANT_ROW_SHIFT) & QUADRANT_ROW_MASK # glossary: bit-field
          quadrant_column = vram_address & QUADRANT_COLUMN_MASK # glossary: bitwise-and
          @palette = (attribute >> (quadrant_row | quadrant_column)) & PALETTE_MASK # glossary: bitwise-or, bit-field
        end

        def fetch_pattern_low
          @pattern_low = @bus.read(pattern_row_address)
        end

        def fetch_pattern_high
          @pattern_high = @bus.read(pattern_row_address + HIGH_PLANE_OFFSET)
        end

        private

        # The tile's row of fine Y in plane 0.
        def pattern_row_address
          fine_y = @scroll_registers.vram_address >> ScrollRegisters::FINE_Y_SHIFT # glossary: bit-field
          @pattern_table | (@tile << TILE_SIZE_SHIFT) | fine_y # glossary: place-bit-field, bitwise-or
        end
      end
    end
  end
end
