# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Sprite 0 hit (https://www.nesdev.org/wiki/PPU_OAM): "when an opaque pixel of sprite 0 overlaps an opaque pixel
      # of the background", the PPU "sets bit 6 of PPUSTATUS", except "At x=255, for an obscure reason related to the
      # pixel pipeline". PriorityMultiplexer asks only where both pixels are opaque and visible, which already rules out
      # disabled layers and the hidden leftmost columns. The flag is set on the dot the pixel is composed, x + 1, one
      # dot before NESdev's "as if the image starts at cycle 2" (plan 14, decision 9). Hot path: once per pixel where
      # a sprite overlaps the background.
      class SpriteZeroHit
        LAST_COLUMN = Picture::WIDTH - 1

        def initialize(status:)
          @status = status
        end

        # A sprite pixel at column x overlaps an opaque background pixel.
        def check(x_position, sprite_entry)
          return if (sprite_entry & SpriteLine::SPRITE_ZERO_FLAG) == 0 # glossary: flag-clear

          @status.sprite_zero_hit unless x_position == LAST_COLUMN
        end
      end
    end
  end
end
