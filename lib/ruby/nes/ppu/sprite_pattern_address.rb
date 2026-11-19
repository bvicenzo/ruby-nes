# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The pattern address of a sprite's row, one strategy per sprite size (PPUCTRL bit 5, "Sprite size (0: 8x8 pixels;
      # 1: 8x16 pixels)", https://www.nesdev.org/wiki/PPU_registers): EightByEight and EightBySixteen. Both read attribute
      # bit 7, "Flip sprite vertically" (https://www.nesdev.org/wiki/PPU_OAM), and place the tile number in an address
      # "0HNNNN NNNNPyyy" (https://www.nesdev.org/wiki/PPU_pattern_tables).
      module SpritePatternAddress
        FLIP_VERTICAL_FLAG = 0x80
        TILE_SHIFT = 4
      end
    end
  end
end

require_relative 'sprite_pattern_address/eight_by_eight'
require_relative 'sprite_pattern_address/eight_by_sixteen'
