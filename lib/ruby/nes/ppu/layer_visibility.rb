# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Which pixels of a layer show (https://www.nesdev.org/wiki/PPU_registers, PPUMASK, told by the Ppu): the
      # background with bit 3 "Enable background rendering" and bit 1 "Show background in leftmost 8 pixels of screen,
      # 0: Hide"; the sprites with bit 4 "Enable sprite rendering" and bit 2 "Show sprites in leftmost 8 pixels of
      # screen, 0: Hide" (plan 14, decision 7). "If one component is enabled and the other is not, the disabled
      # component is simply treated as transparent"; hidden columns are "transparent and thus drawing the backdrop color
      # there". A pixel whose pattern value is 0 is transparent (https://www.nesdev.org/wiki/PPU_palettes): entry 0,
      # the backdrop for the background and no pixel for the sprites, whose line entries keep their flags (bits 6-5).
      # The two settings reduce to the first column a pixel may show in. Hot path: one call per layer per visible dot.
      class LayerVisibility
        # A pixel's pattern value, bits 1-0 of its palette entry.
        PATTERN_MASK = 0x03
        BACKDROP_ENTRY = Picture::BACKDROP_ENTRY
        # The leftmost 8 columns PPUMASK bit 1 or 2 hides; past the last column, the whole layer.
        LEFT_COLUMNS = 8
        NO_COLUMN = Picture::WIDTH

        def initialize(enabled: false, left_columns_shown: false)
          @enabled = enabled
          @left_columns_shown = left_columns_shown
          update_first_visible_column
        end

        def enabled=(enabled)
          @enabled = enabled
          update_first_visible_column
        end

        def left_columns_shown=(shown)
          @left_columns_shown = shown
          update_first_visible_column
        end

        # The palette entry shown at column x for a pixel: 0 when hidden or transparent.
        def palette_entry(x_position, pixel)
          return BACKDROP_ENTRY if x_position < @first_visible_column

          pixel.anybits?(PATTERN_MASK) ? pixel : BACKDROP_ENTRY
        end

        private

        def update_first_visible_column
          @first_visible_column =
            if !@enabled then NO_COLUMN
            elsif @left_columns_shown then 0
            else LEFT_COLUMNS
            end
        end
      end
    end
  end
end
