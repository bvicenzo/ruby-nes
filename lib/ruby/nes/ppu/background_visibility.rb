# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Which background pixels show (https://www.nesdev.org/wiki/PPU_registers, PPUMASK, told by the Ppu): bit 3
      # "Enable background rendering"; bit 1 "Show background in leftmost 8 pixels of screen, 0: Hide", hiding them
      # "making them transparent and thus drawing the backdrop color there". A pixel whose pattern value is 0 is
      # transparent and shows the backdrop, palette entry 0 (https://www.nesdev.org/wiki/PPU_palettes). The two flags
      # reduce to the first column a pixel may show in. Hot path: one call per visible dot while rendering.
      class BackgroundVisibility
        # A pixel's pattern value, bits 1-0 of its palette entry.
        PATTERN_MASK = 0x03
        BACKDROP_ENTRY = Picture::BACKDROP_ENTRY
        # The leftmost 8 columns PPUMASK bit 1 hides; past the last column, the whole background.
        LEFT_COLUMNS = 8
        NO_COLUMN = Picture::WIDTH

        def initialize(background_enabled: false, left_columns_shown: false)
          @background_enabled = background_enabled
          @left_columns_shown = left_columns_shown
          update_first_visible_column
        end

        def background_enabled=(enabled)
          @background_enabled = enabled
          update_first_visible_column
        end

        def left_columns_shown=(shown)
          @left_columns_shown = shown
          update_first_visible_column
        end

        # The palette entry drawn at column x for a 4-bit background pixel.
        def palette_entry(x_position, pixel)
          return BACKDROP_ENTRY if x_position < @first_visible_column

          pixel.anybits?(PATTERN_MASK) ? pixel : BACKDROP_ENTRY
        end

        private

        def update_first_visible_column
          @first_visible_column =
            if !@background_enabled then NO_COLUMN
            elsif @left_columns_shown then 0
            else LEFT_COLUMNS
            end
        end
      end
    end
  end
end
