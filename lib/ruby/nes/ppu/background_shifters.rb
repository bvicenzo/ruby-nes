# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The background's shift registers (https://www.nesdev.org/wiki/PPU_rendering): two 16-bit registers of pattern
      # data, plane 0 and plane 1, and two of attribute data. The hardware feeds 8-bit attribute registers from 1-bit
      # latches; here they are 16-bit registers whose new byte repeats the palette bit, which outputs the same pixels
      # (plan 13). A reload puts the next tile in the low byte while the high byte keeps the tile on screen; each dot
      # the pixel under fine X is read from bit 15 down and the registers shift one bit up. The pixel is 4 bits: the
      # palette in bits 3-2, plane 1 in bit 1, plane 0 in bit 0 (https://www.nesdev.org/wiki/PPU_palettes). Hot path:
      # called every dot while rendering. Specs may give the registers as keywords.
      class BackgroundShifters
        # The pixel under fine X 0 is bit 15.
        FIRST_PIXEL_BIT = 15
        # A reload replaces the low byte, the next tile; a shift keeps 16 bits.
        ON_SCREEN_MASK = 0xFF00
        REGISTER_MASK = Bits::WORD_MASK
        # A palette bit, 0 or 1, fills the 8 bits of a tile.
        ATTRIBUTE_BYTE = [0x00, 0xFF].freeze
        PALETTE_HIGH_BIT_SHIFT = 1
        # The pixel's fields.
        PATTERN_HIGH_SHIFT = 1
        PALETTE_LOW_SHIFT = 2
        PALETTE_HIGH_SHIFT = 3

        def initialize(pattern_low: 0, pattern_high: 0, attribute_low: 0, attribute_high: 0)
          @pattern_low = pattern_low
          @pattern_high = pattern_high
          @attribute_low = attribute_low
          @attribute_high = attribute_high
        end

        # The next tile's two planes and its palette (0-3) go behind the tile on screen.
        def reload(pattern_low, pattern_high, palette)
          @pattern_low = (@pattern_low & ON_SCREEN_MASK) | pattern_low # glossary: place-bit-field
          @pattern_high = (@pattern_high & ON_SCREEN_MASK) | pattern_high # glossary: place-bit-field
          attribute_low = ATTRIBUTE_BYTE[palette & 1] # glossary: bit-at
          attribute_high = ATTRIBUTE_BYTE[palette >> PALETTE_HIGH_BIT_SHIFT] # glossary: bit-at
          @attribute_low = (@attribute_low & ON_SCREEN_MASK) | attribute_low # glossary: place-bit-field
          @attribute_high = (@attribute_high & ON_SCREEN_MASK) | attribute_high # glossary: place-bit-field
        end

        # One bit up; a reload every 8 shifts drops what passes bit 15.
        def shift
          @pattern_low = (@pattern_low << 1) & REGISTER_MASK # glossary: shift-left, low-bits
          @pattern_high = (@pattern_high << 1) & REGISTER_MASK # glossary: shift-left, low-bits
          @attribute_low = (@attribute_low << 1) & REGISTER_MASK # glossary: shift-left, low-bits
          @attribute_high = (@attribute_high << 1) & REGISTER_MASK # glossary: shift-left, low-bits
        end

        # The 4-bit pixel fine X selects: palette in bits 3-2, pattern in bits 1-0.
        def pixel(fine_x)
          bit = FIRST_PIXEL_BIT - fine_x
          palette_high = ((@attribute_high >> bit) & 1) << PALETTE_HIGH_SHIFT # glossary: bit-at, place-bit-field
          palette_low = ((@attribute_low >> bit) & 1) << PALETTE_LOW_SHIFT # glossary: bit-at, place-bit-field
          pattern_high = ((@pattern_high >> bit) & 1) << PATTERN_HIGH_SHIFT # glossary: bit-at, place-bit-field
          palette_high | palette_low | pattern_high | ((@pattern_low >> bit) & 1) # glossary: bitwise-or, bit-at
        end
      end
    end
  end
end
