# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # The ROM browser's screen (plan 37, decision 3), composed as an NES frame: 256 × 240 palette indices
        # (docs/architecture.md, Frame buffer contract) the window draws as it draws a game's, in colours of the NES
        # palette. Its text sits on the 8 × 8 grid an NES draws its tiles on, within lines 8-231, which
        # `--crop-overscan` keeps (https://www.nesdev.org/wiki/Overscan). At the top, framed, the preview of the ROM in
        # focus at half size, or in its place the reason the ROM cannot be run, or NO_PREVIEW; under it the focus's
        # tags; then LIST_ROWS rows of the list, with the cursor, the marks (Screens::PixelFont) and arrows where the
        # list goes on. One frame buffer for the life of the screen (a Screens::Canvas), composed again on each call.
        # Off the hot path: once per menu frame, about 0.6 ms under YJIT.
        class Screen
          include Screens::Colours
          include Screens::Layout

          COLUMNS = Screens::Canvas::COLUMNS
          NO_PREVIEW = 'NO PREVIEW YET'
          NAME_COLUMNS = 26
          # The arrows where the list goes on, in column 30.
          ARROW_COLUMN = 30
          CURSOR = Screens::PixelFont::CURSOR
          BATTERY_SAVE_MARK = Screens::PixelFont::BATTERY_SAVE_MARK
          SAVE_STATE_MARK = Screens::PixelFont::SAVE_STATE_MARK
          MORE_ABOVE = Screens::PixelFont::MORE_ABOVE
          MORE_BELOW = Screens::PixelFont::MORE_BELOW
          # With no ROM: what is said, and the folder's last characters.
          NO_ROMS = 'NO ROMS IN'
          NO_ROMS_ROW = 13
          FOLDER_ROW = 15
          FOLDER_COLUMNS = 30
          WORD = /\S+/

          def initialize
            @canvas = Screens::Canvas.new(background: BACKGROUND)
          end

          # The screen of `roms` (Browser::Rom), the focus and the rows shown by `cursor` (Screens::Cursor), with the
          # focus's picture, `preview_frame` (a frame buffer), or nil, and the reason it cannot be run, `problem`
          # (printable), or nil.
          def list(roms:, cursor:, preview_frame:, problem:)
            @canvas.clear
            draw_preview(preview_frame, problem)
            @canvas.centred(roms.fetch(cursor.focus).tags[0, COLUMNS], row: CAPTION_ROW, colour: QUIET)
            cursor.visible.each_with_index { |index, row| draw_row(roms, index, cursor, LIST_TOP_ROW + row) }
            @canvas.frame_buffer
          end

          # The screen of a `folder` that holds no ROM.
          def empty(folder)
            @canvas.clear
            @canvas.centred(NO_ROMS, row: NO_ROMS_ROW, colour: TEXT)
            folder_end = Screens::PixelFont.printable(folder).chars.last(FOLDER_COLUMNS).join
            @canvas.centred(folder_end, row: FOLDER_ROW, colour: QUIET)
            @canvas.frame_buffer
          end

          private

          def draw_preview(preview_frame, problem)
            @canvas.frame(**PREVIEW_AREA, colour: QUIET)
            return draw_in_preview(wrapped(problem), colour: WARNING) if problem
            return draw_in_preview([NO_PREVIEW], colour: QUIET) unless preview_frame

            @canvas.picture(preview_frame, left: PREVIEW_LEFT, top: PREVIEW_TOP, scale: PREVIEW_SCALE)
          end

          # `lines` centred in the preview, around its middle row.
          def draw_in_preview(lines, colour:)
            first_row = PREVIEW_MIDDLE_ROW - (lines.size / 2)
            lines.each_with_index do |line, index|
              @canvas.centred(line, row: first_row + index, colour:, columns: PREVIEW_CELLS)
            end
          end

          # `text` in lines that fit in the preview's width, broken between words.
          def wrapped(text)
            text.scan(WORD).each_with_object([]) do |word, lines|
              if lines.any? && (lines.last.size + 1 + word.size) <= PREVIEW_COLUMNS
                lines.last << ' ' << word
              else
                lines << word.dup
              end
            end
          end

          def draw_row(roms, index, cursor, row)
            rom = roms.fetch(index)
            draw(CURSOR, column: CURSOR_COLUMN, row:, colour: TEXT) if index == cursor.focus
            draw(rom.name[0, NAME_COLUMNS], column: NAME_COLUMN, row:, colour: rom.playable? ? TEXT : QUIET)
            draw(BATTERY_SAVE_MARK, column: BATTERY_SAVE_COLUMN, row:, colour: WARNING) if rom.battery_save
            draw(SAVE_STATE_MARK, column: SAVE_STATES_COLUMN, row:, colour: HIGHLIGHT) if rom.save_states
            draw_arrow(index, roms.size, cursor.visible, row)
          end

          def draw_arrow(index, size, visible, row)
            more_above = index == visible.min && index.positive?
            more_below = index == visible.max && index < size - 1
            draw(MORE_ABOVE, column: ARROW_COLUMN, row:, colour: QUIET) if more_above
            draw(MORE_BELOW, column: ARROW_COLUMN, row:, colour: QUIET) if more_below
          end

          def draw(text, column:, row:, colour:)
            @canvas.text(text, column:, row:, colour:)
          end
        end
      end
    end
  end
end
