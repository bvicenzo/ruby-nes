# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Which scanlines a sprite covers. Its Y is "delayed by one scanline" (https://www.nesdev.org/wiki/PPU_OAM) and
      # the evaluation on a scanline selects the sprites "in range" for the next one
      # (https://www.nesdev.org/wiki/PPU_sprite_evaluation): a sprite is in range on the scanlines Y to Y + height - 1,
      # a derivation, since the page gives no formula (plan 14). Hot path: once per sprite per evaluated scanline.
      module SpriteRows
        module_function

        # Whether a sprite whose OAM Y is `y_position` and whose height is 8 or 16 covers the scanline.
        def in_range?(y_position, scanline, height)
          row = scanline - y_position
          row >= 0 && row < height
        end
      end
    end
  end
end
