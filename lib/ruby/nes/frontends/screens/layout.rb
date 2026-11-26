# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Screens
        # Where the full-screen menus place things (plan 37, decision 3; shared since plan 38): the ROM browser's list
        # and the pause menu's slot picker. Everything stays within lines 8-231, which `--crop-overscan` keeps
        # (https://www.nesdev.org/wiki/Overscan).
        module Layout
          CELL_SIZE = Canvas::CELL_SIZE
          # A picture at half size, its top left corner at column 64 of line 9, framed by a line whose top edge, line 8,
          # is the first an overscan crop keeps; text in its place is centred around its middle row.
          PREVIEW_SCALE = 2
          PREVIEW_WIDTH = Canvas::WIDTH / PREVIEW_SCALE
          PREVIEW_HEIGHT = Canvas::HEIGHT / PREVIEW_SCALE
          PREVIEW_LEFT = 8 * CELL_SIZE
          PREVIEW_TOP = CELL_SIZE + 1
          PREVIEW_COLUMNS = PREVIEW_WIDTH / CELL_SIZE
          PREVIEW_AREA = { left: PREVIEW_LEFT, top: PREVIEW_TOP, width: PREVIEW_WIDTH, height: PREVIEW_HEIGHT }.freeze
          PREVIEW_CELLS = (PREVIEW_LEFT / CELL_SIZE)...((PREVIEW_LEFT / CELL_SIZE) + PREVIEW_COLUMNS)
          PREVIEW_MIDDLE_ROW = 8
          # The row under the picture: the ROM's tags, the slot picker's title.
          CAPTION_ROW = 17
          # The list: rows 19 to 28, past a blank row; the cursor in column 1, the name from column 2, the marks in
          # columns 28 and 29.
          LIST_TOP_ROW = 19
          LIST_ROWS = 10
          CURSOR_COLUMN = 1
          NAME_COLUMN = 2
          BATTERY_SAVE_COLUMN = 28
          SAVE_STATES_COLUMN = 29
        end
      end
    end
  end
end
