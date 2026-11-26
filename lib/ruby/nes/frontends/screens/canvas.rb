# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Screens
        # What the menus draw with (plan 38, out of plan 37's Browser::Screen): one NES frame of 256 × 240 palette
        # indices (docs/architecture.md, Frame buffer contract) for the canvas's life, drawn by the window as a game's.
        # Text sits on the 8 × 8 grid an NES draws its tiles on, in Screens::PixelFont; areas, their frames and scaled
        # pictures are in pixels. Nothing is drawn outside what each call names. Off the hot path: once per menu frame.
        class Canvas
          WIDTH = Ppu::Picture::WIDTH
          HEIGHT = Ppu::Picture::HEIGHT
          CELL_SIZE = PixelFont::CELL_SIZE
          COLUMNS = WIDTH / CELL_SIZE
          ROWS = HEIGHT / CELL_SIZE

          # The frame drawn into, the same array for the canvas's life.
          attr_reader :frame_buffer

          # A canvas of `background`, a colour of the NES palette (Frontends::Palette).
          def initialize(background:)
            @background = background
            @frame_buffer = Array.new(WIDTH * HEIGHT, background)
          end

          def clear
            @frame_buffer.fill(@background)
          end

          # Takes the pixels of `frame`, a frame buffer, which stays apart.
          def copy(frame)
            @frame_buffer.replace(frame)
          end

          # `text`, printable (Screens::PixelFont), from the cell at `column` and `row`.
          def text(text, column:, row:, colour:)
            PixelFont.draw(text, @frame_buffer, left: column * CELL_SIZE, top: row * CELL_SIZE, colour:)
          end

          # `text` in `row`, centred within `columns` (the whole row by default), the odd column left over on the right.
          def centred(text, row:, colour:, columns: 0...COLUMNS)
            text(text, column: columns.first + ((columns.size - text.size) / 2), row:, colour:)
          end

          # The area of `width` × `height` pixels whose top left corner is at `left`, `top`, all `colour`.
          def fill(left:, top:, width:, height:, colour:)
            (top...(top + height)).each { |row| @frame_buffer.fill(colour, (row * WIDTH) + left, width) }
          end

          # A line of one pixel just outside the area of `width` × `height` pixels at `left`, `top`.
          def frame(left:, top:, width:, height:, colour:)
            fill(left: left - 1, top: top - 1, width: width + 2, height: 1, colour:)
            fill(left: left - 1, top: top + height, width: width + 2, height: 1, colour:)
            fill(left: left - 1, top:, width: 1, height:, colour:)
            fill(left: left + width, top:, width: 1, height:, colour:)
          end

          # `frame`, a frame buffer, at one `scale`th of its size: one pixel in `scale` of one line in `scale`, its top
          # left corner at `left`, `top`.
          def picture(frame, left:, top:, scale:)
            (HEIGHT / scale).times do |row|
              source_row = row * scale * WIDTH
              target_row = ((top + row) * WIDTH) + left
              (WIDTH / scale).times do |column|
                @frame_buffer[target_row + column] = frame[source_row + (column * scale)]
              end
            end
          end
        end
      end
    end
  end
end
