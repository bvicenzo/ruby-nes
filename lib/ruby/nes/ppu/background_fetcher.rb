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
        # Load-time tables by v's low 12 bits, the ones the attribute depends on (plan 30, decision 8): the attribute
        # address, and the factor that brings the quadrant's two bits to bits 7-6, so a constant shift takes them, since
        # YJIT compiles a shift by a varying amount as a method call. Built once at load time; the tags name each bit
        # operation as on the hot paths, as RenderSchedule's tables do.
        PALETTE_TOP_SHIFT = 6

        def self.attribute_address(tile_offset)
          nametable = tile_offset & ATTRIBUTE_NAMETABLE_MASK # glossary: bitwise-and
          row = (tile_offset >> ATTRIBUTE_ROW_SHIFT) & ATTRIBUTE_ROW_MASK # glossary: bit-field
          column = (tile_offset >> ATTRIBUTE_COLUMN_SHIFT) & ATTRIBUTE_COLUMN_MASK # glossary: bit-field
          ATTRIBUTE_ADDRESS_BASE | nametable | row | column # glossary: bitwise-or
        end

        def self.quadrant_factor(tile_offset)
          quadrant_row = (tile_offset >> QUADRANT_ROW_SHIFT) & QUADRANT_ROW_MASK # glossary: bit-field
          quadrant_column = tile_offset & QUADRANT_COLUMN_MASK # glossary: bitwise-and
          1 << (PALETTE_TOP_SHIFT - (quadrant_row | quadrant_column)) # glossary: shift-left, bitwise-or
        end
        private_class_method :attribute_address, :quadrant_factor

        ATTRIBUTE_ADDRESSES = Array.new(TILE_ADDRESS_MASK + 1) { attribute_address(it) }.freeze
        QUADRANT_FACTORS = Array.new(TILE_ADDRESS_MASK + 1) { quadrant_factor(it) }.freeze
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
          tile_offset = @scroll_registers.vram_address & TILE_ADDRESS_MASK # glossary: low-bits
          attribute = @bus.read(ATTRIBUTE_ADDRESSES[tile_offset])
          quadrant_on_top = attribute * QUADRANT_FACTORS[tile_offset]
          @palette = (quadrant_on_top >> PALETTE_TOP_SHIFT) & PALETTE_MASK # glossary: bit-field
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
