# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Chooses the pixel drawn from the background's and the sprites' (https://www.nesdev.org/wiki/PPU_rendering): the
      # "Priority multiplexer decision table" gives the backdrop, "EXT in ($3F00)", when both are transparent, the opaque
      # one when only one is, and with both opaque the sprite when its priority is 0 (in front) and the background when
      # it is 1 (behind). Both entries come through LayerVisibility, so entry 0 is a transparent or hidden pixel; a
      # sprite entry carries SpriteLine's flags, dropped from the entry drawn. Where both are opaque, sprite 0 hit is
      # checked, "regardless of sprite priority" (https://www.nesdev.org/wiki/PPU_OAM). Hot path: one call per pixel.
      class PriorityMultiplexer
        def initialize(sprite_zero_hit:)
          @sprite_zero_hit = sprite_zero_hit
        end

        # The palette entry drawn at column x.
        def palette_entry(x_position, background_entry, sprite_entry)
          return background_entry if sprite_entry.zero?
          return sprite_entry & SpriteLine::PALETTE_ENTRY_MASK if background_entry.zero? # glossary: low-bits

          @sprite_zero_hit.check(x_position, sprite_entry)
          return background_entry if sprite_entry.anybits?(SpriteLine::BEHIND_BACKGROUND_FLAG)

          sprite_entry & SpriteLine::PALETTE_ENTRY_MASK # glossary: low-bits
        end
      end
    end
  end
end
