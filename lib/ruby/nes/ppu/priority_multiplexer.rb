# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Chooses the pixel drawn where the background's and the sprites' are both opaque
      # (https://www.nesdev.org/wiki/PPU_rendering): the "Priority multiplexer decision table" gives the sprite when its
      # priority is 0 (in front) and the background when it is 1 (behind). The renderer draws a lone opaque layer
      # itself and asks only for these pixels (plan 25, decision 7). A sprite entry carries SpriteLine's flags, dropped
      # from the entry drawn. Sprite 0 hit is checked on each, "regardless of sprite priority"
      # (https://www.nesdev.org/wiki/PPU_OAM). Hot path: one call per pixel where the layers overlap.
      class PriorityMultiplexer
        def initialize(sprite_zero_hit:)
          @sprite_zero_hit = sprite_zero_hit
        end

        # The palette entry drawn at column x, both entries opaque.
        def palette_entry(x_position, background_entry, sprite_entry)
          @sprite_zero_hit.check(x_position, sprite_entry)
          return background_entry if (sprite_entry & SpriteLine::BEHIND_BACKGROUND_FLAG) != 0 # glossary: flag-set

          sprite_entry & SpriteLine::PALETTE_ENTRY_MASK # glossary: low-bits
        end
      end
    end
  end
end
