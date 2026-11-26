# frozen_string_literal: true

# Reads a frame buffer the ROM browser composed (plan 37) as text: its 32 × 30 cells of 8 × 8 pixels, each the
# character of Browser::PixelFont whose glyph its pixels other than the background's are, a space when it has none,
# and "#" when they are no glyph (a picture, a frame's line). The browser draws its text on that grid, as an NES game
# draws its tiles.
#
#   ScreenText.rows(frame_buffer)[19] # => " ▶CASTLEVANIA                 ♥  "
module ScreenText
  NO_GLYPH = '#'

  def self.rows(frame_buffer, background: screen::BACKGROUND)
    Array.new(screen::HEIGHT / screen::CELL_SIZE) do |row|
      Array.new(screen::COLUMNS) { |column| character(frame_buffer, row, column, background) }.join
    end
  end

  def self.screen = Ruby::Nes::Frontends::Browser::Screen

  # Glyphs by their pixels; the space has none, so an empty cell reads as one.
  def self.characters
    @characters ||= Ruby::Nes::Frontends::Browser::PixelFont::GLYPHS.to_h { |glyph, offsets| [offsets.sort, glyph] }
  end

  def self.character(frame_buffer, row, column, background)
    cell = screen::CELL_SIZE
    offsets = cell.times.to_a.product(cell.times.to_a).reject do |offset_column, offset_row|
      frame_buffer[(((row * cell) + offset_row) * screen::WIDTH) + (column * cell) + offset_column] == background
    end
    characters.fetch(offsets.sort, NO_GLYPH)
  end

  private_class_method :screen, :characters, :character
end
