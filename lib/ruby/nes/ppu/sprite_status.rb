# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The sprite flags of PPUSTATUS (https://www.nesdev.org/wiki/PPU_registers): bit 5, the "Sprite overflow flag",
      # which the evaluation sets, and bit 6, the "Sprite 0 hit flag", which the priority multiplexer sets. Both stay set
      # until they are "automatically cleared on dot 1 of the prerender scanline"; reading PPUSTATUS leaves them.
      class SpriteStatus
        OVERFLOW_FLAG = 0x20
        SPRITE_ZERO_HIT_FLAG = 0x40

        # PPUSTATUS bits 6-5.
        attr_reader :bits

        def initialize
          @bits = 0
        end

        def overflow_found
          @bits |= OVERFLOW_FLAG # glossary: set-flag
        end

        def sprite_zero_hit
          @bits |= SPRITE_ZERO_HIT_FLAG # glossary: set-flag
        end

        def clear
          @bits = 0
        end
      end
    end
  end
end
