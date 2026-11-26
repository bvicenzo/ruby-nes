# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Pause
        # The pause menu's screens (plan 38), NES frames of palette indices on the 8 × 8 grid, as the ROM browser's
        # (plan 37, decision 3), within lines 8-231 (https://www.nesdev.org/wiki/Overscan). The menu is a box of
        # BOX_COLUMNS columns, centred over a picture (the paused game, dimmed), framed by a grey line just outside it:
        # its title, a blank row, then the entries (Screens::Choices), the cursor on the focus, white or grey when they
        # cannot be chosen. The slot picker is laid out as the browser's list (Screens::Layout): the picture of the
        # slot in focus at half size, or EMPTY in its place, the title under it, then the slots, a star on those with a
        # state. One frame buffer for the life of the screen, composed again on each call. Off the hot path: once per
        # menu frame.
        class Screen
          include Screens::Colours
          include Screens::Layout

          ROWS = Screens::Canvas::ROWS
          BOX_COLUMNS = 16
          BOX_LEFT_COLUMN = (Screens::Canvas::COLUMNS - BOX_COLUMNS) / 2
          # Rows of the box besides its entries: a margin, the title, a blank row, and a margin.
          BOX_OTHER_ROWS = 4
          ENTRIES_FIRST_ROW = 3
          MENU_CURSOR_COLUMN = BOX_LEFT_COLUMN + 1
          LABEL_COLUMN = BOX_LEFT_COLUMN + 2
          EMPTY = 'EMPTY'
          SLOT_LABEL = 'SLOT '

          def initialize
            @canvas = Screens::Canvas.new(background: BACKGROUND)
          end

          # The menu over `background`, a frame buffer, titled `title`, its entries `choices` (Screens::Choices),
          # each written as `labels` names it.
          def menu(background:, title:, choices:, labels:)
            @canvas.copy(background)
            top_row = draw_box(choices.entries.size)
            @canvas.centred(title, row: top_row + 1, colour: HIGHLIGHT)
            choices.entries.each_with_index do |entry, index|
              focused = index == choices.focus
              available = choices.available?(entry)
              row = top_row + ENTRIES_FIRST_ROW + index
              draw_entry(labels.fetch(entry), focused:, available:, column: MENU_CURSOR_COLUMN, row:)
            end
            @canvas.frame_buffer
          end

          # The slot picker titled `title`, its slots `choices` (Screens::Choices of slot numbers), those in `written`
          # holding a state, with the picture of the slot in focus, `picture` (a frame buffer), or nil.
          def slots(title:, choices:, written:, picture:)
            @canvas.clear
            draw_picture(picture)
            @canvas.centred(title, row: CAPTION_ROW, colour: HIGHLIGHT)
            choices.entries.each_with_index do |slot, index|
              focused = index == choices.focus
              available = choices.available?(slot)
              row = LIST_TOP_ROW + index
              draw_entry("#{SLOT_LABEL}#{slot}", focused:, available:, column: CURSOR_COLUMN, row:)
              mark = Screens::PixelFont::SAVE_STATE_MARK
              @canvas.text(mark, column: SAVE_STATES_COLUMN, row:, colour: HIGHLIGHT) if written.include?(slot)
            end
            @canvas.frame_buffer
          end

          private

          # A box of BOX_COLUMNS columns and the rows `entries` need, centred; its top row.
          def draw_box(entries)
            rows = entries + BOX_OTHER_ROWS
            top_row = (ROWS - rows) / 2
            area = { left: BOX_LEFT_COLUMN * CELL_SIZE, top: top_row * CELL_SIZE, width: BOX_COLUMNS * CELL_SIZE }
            @canvas.fill(**area, height: rows * CELL_SIZE, colour: BACKGROUND)
            @canvas.frame(**area, height: rows * CELL_SIZE, colour: QUIET)
            top_row
          end

          def draw_picture(picture)
            @canvas.frame(**PREVIEW_AREA, colour: QUIET)
            return @canvas.picture(picture, left: PREVIEW_LEFT, top: PREVIEW_TOP, scale: PREVIEW_SCALE) if picture

            @canvas.centred(EMPTY, row: PREVIEW_MIDDLE_ROW, colour: QUIET, columns: PREVIEW_CELLS)
          end

          # The cursor in `column` when the entry is `focused`, and `label` after it, grey unless `available`.
          def draw_entry(label, focused:, available:, column:, row:)
            @canvas.text(Screens::PixelFont::CURSOR, column:, row:, colour: TEXT) if focused
            @canvas.text(label, column: column + 1, row:, colour: available ? TEXT : QUIET)
          end
        end
      end
    end
  end
end
