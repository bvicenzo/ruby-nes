# frozen_string_literal: true

# Reads a frame buffer a menu composed (plans 37 and 38) as text: its 32 × 30 cells of 8 × 8 pixels, each the
# character of Screens::PixelFont whose glyph its pixels other than the background's are, a space when it has none,
# and "#" when they are no glyph (a picture, a frame's line). The menus draw their text on that grid, as an NES game
# draws its tiles.
#
#   ScreenText.rows(frame_buffer)[19] # => " ▶CASTLEVANIA                 ♥  "
#   ScreenText.colours(frame_buffer, row: 19) # => [0x30, 0x16], the colours drawn in a row, in order of appearance
module ScreenText
  NO_GLYPH = '#'

  def self.rows(frame_buffer, background: background_colour)
    Array.new(screen::HEIGHT / screen::CELL_SIZE) do |row|
      Array.new(screen::COLUMNS) { |column| character(frame_buffer, row, column, background) }.join
    end
  end

  # The colours other than the background's in the cells of `row`, from `columns`.
  def self.colours(frame_buffer, row:, columns: 0...screen::COLUMNS, background: background_colour)
    cell = screen::CELL_SIZE
    pixels = cell.times.flat_map do |offset_row|
      frame_buffer[(((row * cell) + offset_row) * screen::WIDTH) + (columns.first * cell), columns.count * cell]
    end
    pixels.uniq - [background]
  end

  def self.background_colour = Ruby::Nes::Frontends::Screens::Colours::BACKGROUND

  def self.screen = Ruby::Nes::Frontends::Screens::Canvas

  # Glyphs by their pixels; the space has none, so an empty cell reads as one.
  def self.characters
    @characters ||= Ruby::Nes::Frontends::Screens::PixelFont::GLYPHS.to_h { |glyph, offsets| [offsets.sort, glyph] }
  end

  def self.character(frame_buffer, row, column, background)
    cell = screen::CELL_SIZE
    offsets = cell.times.to_a.product(cell.times.to_a).reject do |offset_column, offset_row|
      frame_buffer[(((row * cell) + offset_row) * screen::WIDTH) + (column * cell) + offset_column] == background
    end
    characters.fetch(offsets.sort, NO_GLYPH)
  end

  private_class_method :background_colour, :screen, :characters, :character
end
