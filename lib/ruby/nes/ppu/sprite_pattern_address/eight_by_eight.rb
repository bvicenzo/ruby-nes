# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      module SpritePatternAddress
        # The pattern address of an 8×8 sprite's row (https://www.nesdev.org/wiki/PPU_OAM): byte 1 "is the tile number
        # of this sprite within the pattern table selected in bit 3 of PPUCTRL", told by the Ppu; attribute bit 7 is
        # "Flip sprite vertically". The address is "0HNNNN NNNNPyyy", plane 0 (https://www.nesdev.org/wiki/PPU_pattern_tables);
        # a row past the tile (an empty slot's) keeps its 3 low bits. Hot path: one call per sprite fetch.
        class EightByEight
          HEIGHT = 8
          LAST_ROW = HEIGHT - 1

          # The sprite pattern table's base address, $0000 or $1000.
          attr_writer :pattern_table

          def initialize(pattern_table: FIRST_PATTERN_TABLE)
            @pattern_table = pattern_table
          end

          def height = HEIGHT

          def address(tile, row, attributes)
            fine_y = row & LAST_ROW # glossary: low-bits
            fine_y = LAST_ROW - fine_y if attributes.anybits?(FLIP_VERTICAL_FLAG)
            @pattern_table | (tile << TILE_SHIFT) | fine_y # glossary: place-bit-field, bitwise-or
          end
        end
      end
    end
  end
end
