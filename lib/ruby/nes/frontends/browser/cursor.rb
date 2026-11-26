# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # The focus in the browser's list and the rows of it shown (plan 37, scope 3): the focus starts on the first ROM
        # and moves by rows or pages, stopping at the ends; the rows shown scroll only as far as needed to keep it in
        # sight. Off the hot path: once per press.
        class Cursor
          # The index of the ROM in focus.
          attr_reader :focus

          # A list of `size` ROMs, at least one, `rows` of them shown at a time.
          def initialize(size:, rows:)
            @size = size
            @rows = rows
            @focus = 0
            @first_visible = 0
          end

          # Moves the focus `by` ROMs, down when positive.
          def move(by)
            @focus = (@focus + by).clamp(0, @size - 1)
            @first_visible = @first_visible.clamp(@focus - @rows + 1, @focus)
          end

          # Moves the focus `by` pages of the rows shown.
          def page(by) = move(by * @rows)

          # The indexes of the ROMs shown.
          def visible = @first_visible...[@first_visible + @rows, @size].min
        end
      end
    end
  end
end
