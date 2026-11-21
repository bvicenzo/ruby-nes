# frozen_string_literal: true

# The pixels of a band of rows of a frame buffer, 256 pixels a row (docs/architecture.md, Frame buffer contract), with
# an optional rectangle left out: a part of the picture allowed to change, such as a status bar's timer.
#
#   status_bar = FrameRegion.new(rows: 196..239, hole_rows: 212..217, hole_columns: 152..159)
#   status_bar.pixels(console.ppu.frame_buffer)
class FrameRegion
  WIDTH = Ruby::Nes::Ppu::Picture::WIDTH
  NO_HOLE = (0...0)

  def initialize(rows:, hole_rows: NO_HOLE, hole_columns: NO_HOLE)
    @rows = rows
    @hole_rows = hole_rows
    @hole_columns = hole_columns
  end

  # The region's pixels, row by row, without the hole's.
  def pixels(frame) = @rows.flat_map { |row| row_pixels(frame, row) }

  private

  def row_pixels(frame, row)
    pixels = frame[row * WIDTH, WIDTH]
    return pixels unless @hole_rows.cover?(row)

    pixels.reject.with_index { |_pixel, column| @hole_columns.cover?(column) }
  end
end
