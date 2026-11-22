# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Which columns of a layer show (https://www.nesdev.org/wiki/PPU_registers, PPUMASK, told by the Ppu): the
      # background with bit 3 "Enable background rendering" and bit 1 "Show background in leftmost 8 pixels of screen,
      # 0: Hide"; the sprites with bit 4 "Enable sprite rendering" and bit 2 "Show sprites in leftmost 8 pixels of
      # screen, 0: Hide" (plan 14, decision 7). "If one component is enabled and the other is not, the disabled
      # component is simply treated as transparent"; hidden columns are "transparent and thus drawing the backdrop color
      # there". The two settings reduce to the first column a pixel may show in, which the renderer reads once per
      # layer per visible dot (plan 25, decision 7).
      class LayerVisibility
        # The leftmost 8 columns PPUMASK bit 1 or 2 hides; past the last column, the whole layer.
        LEFT_COLUMNS = 8
        NO_COLUMN = Picture::WIDTH

        # The first column the layer shows; 256 when it shows none.
        attr_reader :first_visible_column

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
