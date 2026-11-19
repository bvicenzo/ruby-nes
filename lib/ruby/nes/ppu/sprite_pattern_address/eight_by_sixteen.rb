# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      module SpritePatternAddress
        # The pattern address of an 8×16 sprite's row (https://www.nesdev.org/wiki/PPU_OAM): "the PPU ignores the
        # pattern table selection and selects a pattern table from bit 0 of this number"; the rest is the "Tile number of
        # top of sprite (0 to 254; bottom half gets the next tile)"; "In 8x16 mode, vertical flip flips each of the
        # subtiles and also exchanges their position", which is the sprite's 16 rows read from the bottom. The address
        # is "0HNNNN NNNNPyyy", plane 0 (https://www.nesdev.org/wiki/PPU_pattern_tables); a row past the sprite (an
        # empty slot's) keeps its 4 low bits. Hot path: one call per sprite fetch.
        class EightBySixteen
          HEIGHT = 16
          LAST_ROW = HEIGHT - 1
          # Tile bit 0 picks the pattern table; the row's bit 3 picks the bottom tile; bits 2-0 are fine Y.
          PATTERN_TABLE_FLAG = 0x01
          HALF_SHIFT = 3
          FINE_Y_MASK = 0x07

          def height = HEIGHT

          def address(tile, row, attributes)
            sprite_row = row & LAST_ROW # glossary: low-bits
            sprite_row = LAST_ROW - sprite_row if attributes.anybits?(FLIP_VERTICAL_FLAG)
            pattern_table = tile.anybits?(PATTERN_TABLE_FLAG) ? SECOND_PATTERN_TABLE : FIRST_PATTERN_TABLE
            top_tile = tile & ~PATTERN_TABLE_FLAG # glossary: clear-flag
            tile_number = top_tile | (sprite_row >> HALF_SHIFT) # glossary: bit-field, bitwise-or
            fine_y = sprite_row & FINE_Y_MASK # glossary: low-bits
            pattern_table | (tile_number << TILE_SHIFT) | fine_y # glossary: place-bit-field, bitwise-or
          end
        end
      end
    end
  end
end
