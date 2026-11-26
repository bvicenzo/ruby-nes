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
        # tags; then LIST_ROWS rows of the list, with the cursor, the marks (Browser::PixelFont) and arrows where the
        # list goes on. One frame buffer for the life of the screen, composed again on each call. Off the hot path: once
        # per menu frame, about 0.6 ms under YJIT.
        class Screen
          WIDTH = Ppu::Picture::WIDTH
          HEIGHT = Ppu::Picture::HEIGHT
          CELL_SIZE = PixelFont::CELL_SIZE
          COLUMNS = WIDTH / CELL_SIZE
          # Colours of the NES palette (Frontends::Palette): black, white, light grey, red and yellow.
          BACKGROUND = 0x0F
          TEXT = 0x30
          QUIET = 0x10
          WARNING = 0x16
          HIGHLIGHT = 0x28
          # The preview: a frame at half size, its top left corner at column 64 of line 9, framed by a line of QUIET
          # whose top edge, line 8, is the first an overscan crop keeps.
          PREVIEW_SCALE = 2
          PREVIEW_WIDTH = WIDTH / PREVIEW_SCALE
          PREVIEW_HEIGHT = HEIGHT / PREVIEW_SCALE
          PREVIEW_LEFT = 8 * CELL_SIZE
          PREVIEW_TOP = CELL_SIZE + 1
          PREVIEW_COLUMNS = PREVIEW_WIDTH / CELL_SIZE
          PREVIEW_MIDDLE_ROW = 8
          NO_PREVIEW = 'NO PREVIEW YET'
          TAGS_ROW = 17
          # The list: rows 19 to 28, past a blank row; the cursor in column 1, the name from column 2, the marks in
          # columns 28 and 29, the arrows in column 30.
          LIST_TOP_ROW = 19
          LIST_ROWS = 10
          CURSOR_COLUMN = 1
          NAME_COLUMN = 2
          NAME_COLUMNS = 26
          BATTERY_SAVE_COLUMN = 28
          SAVE_STATES_COLUMN = 29
          ARROW_COLUMN = 30
          # With no ROM: what is said, and the folder's last characters.
          NO_ROMS = 'NO ROMS IN'
          NO_ROMS_ROW = 13
          FOLDER_ROW = 15
          FOLDER_COLUMNS = 30
          WORD = /\S+/

          def initialize
            @frame_buffer = Array.new(WIDTH * HEIGHT, BACKGROUND)
          end

          # The screen of `roms` (Browser::Rom), the focus and the rows shown by `cursor` (Browser::Cursor), with the
          # focus's picture, `preview_frame` (a frame buffer), or nil, and the reason it cannot be run, `problem`
          # (printable), or nil.
          def list(roms:, cursor:, preview_frame:, problem:)
            @frame_buffer.fill(BACKGROUND)
            draw_preview(preview_frame, problem)
            draw_centred(roms.fetch(cursor.focus).tags[0, COLUMNS], row: TAGS_ROW, colour: QUIET)
            cursor.visible.each_with_index { |index, row| draw_row(roms, index, cursor, LIST_TOP_ROW + row) }
            @frame_buffer
          end

          # The screen of a `folder` that holds no ROM.
          def empty(folder)
            @frame_buffer.fill(BACKGROUND)
            draw_centred(NO_ROMS, row: NO_ROMS_ROW, colour: TEXT)
            draw_centred(PixelFont.printable(folder).chars.last(FOLDER_COLUMNS).join, row: FOLDER_ROW, colour: QUIET)
            @frame_buffer
          end

          private

          def draw_preview(preview_frame, problem)
            draw_preview_frame
            return draw_in_preview(wrapped(problem), colour: WARNING) if problem
            return draw_in_preview([NO_PREVIEW], colour: QUIET) unless preview_frame

            PREVIEW_HEIGHT.times do |row|
              source_row = row * PREVIEW_SCALE * WIDTH
              target_row = ((PREVIEW_TOP + row) * WIDTH) + PREVIEW_LEFT
              PREVIEW_WIDTH.times do |column|
                @frame_buffer[target_row + column] = preview_frame[source_row + (column * PREVIEW_SCALE)]
              end
            end
          end

          # A line of one pixel just outside the preview.
          def draw_preview_frame
            left = PREVIEW_LEFT - 1
            right = PREVIEW_LEFT + PREVIEW_WIDTH
            top = PREVIEW_TOP - 1
            bottom = PREVIEW_TOP + PREVIEW_HEIGHT
            (left..right).each do |column|
              @frame_buffer[(top * WIDTH) + column] = QUIET
              @frame_buffer[(bottom * WIDTH) + column] = QUIET
            end
            (top..bottom).each do |row|
              @frame_buffer[(row * WIDTH) + left] = QUIET
              @frame_buffer[(row * WIDTH) + right] = QUIET
            end
          end

          # `lines` centred in the preview, around its middle row.
          def draw_in_preview(lines, colour:)
            first_row = PREVIEW_MIDDLE_ROW - (lines.size / 2)
            lines.each_with_index do |line, index|
              column = (PREVIEW_LEFT / CELL_SIZE) + ((PREVIEW_COLUMNS - line.size) / 2)
              draw(line, column:, row: first_row + index, colour:)
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
            draw(PixelFont::CURSOR, column: CURSOR_COLUMN, row:, colour: TEXT) if index == cursor.focus
            draw(rom.name[0, NAME_COLUMNS], column: NAME_COLUMN, row:, colour: rom.playable? ? TEXT : QUIET)
            draw(PixelFont::BATTERY_SAVE_MARK, column: BATTERY_SAVE_COLUMN, row:, colour: WARNING) if rom.battery_save
            draw(PixelFont::SAVE_STATE_MARK, column: SAVE_STATES_COLUMN, row:, colour: HIGHLIGHT) if rom.save_states
            draw_arrow(index, roms.size, cursor.visible, row)
          end

          def draw_arrow(index, size, visible, row)
            more_above = index == visible.min && index.positive?
            more_below = index == visible.max && index < size - 1
            draw(PixelFont::MORE_ABOVE, column: ARROW_COLUMN, row:, colour: QUIET) if more_above
            draw(PixelFont::MORE_BELOW, column: ARROW_COLUMN, row:, colour: QUIET) if more_below
          end

          def draw_centred(text, row:, colour:)
            draw(text, column: (COLUMNS - text.size) / 2, row:, colour:)
          end

          def draw(text, column:, row:, colour:)
            PixelFont.draw(text, @frame_buffer, left: column * CELL_SIZE, top: row * CELL_SIZE, colour:)
          end
        end
      end
    end
  end
end
