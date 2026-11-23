# frozen_string_literal: true

# A Ppu::Picture whose palette RAM gives each entry a colour of its own, $20 above the entry ($20-$3F fit in the 6 bits
# of a colour), so the pixels a renderer draws into it tell which palette entry it chose; a pixel never drawn stays 0.
# Entries $10, $14, $18 and $1C share their storage with $00, $04, $08 and $0C
# (https://www.nesdev.org/wiki/PPU_palettes), so they read as those.
#
#   picture = PaletteEntryPicture.build
#   PaletteEntryPicture.entries(picture, row: 100, columns: 0..7) # => [0x05, 0x00, ...], nil where nothing was drawn
module PaletteEntryPicture
  COLOUR_OFFSET = 0x20
  WIDTH = Ruby::Nes::Ppu::Picture::WIDTH
  ENTRIES = (0...Ruby::Nes::PpuBus::PaletteRam::ENTRY_COUNT)
  SHARED_ENTRIES = [0x10, 0x14, 0x18, 0x1C].freeze

  def self.build
    palette_ram = Ruby::Nes::PpuBus::PaletteRam.new
    (ENTRIES.to_a - SHARED_ENTRIES).each do |entry|
      palette_ram.write(Ruby::Nes::PpuBus::PALETTE_START + entry, entry + COLOUR_OFFSET)
    end
    Ruby::Nes::Ppu::Picture.new(palette_ram:)
  end

  # The palette entry drawn at each column of the row, nil where nothing was drawn.
  def self.entries(picture, row:, columns:)
    columns.map { |column| entry_of(picture.drawn_frame[(row * WIDTH) + column]) }
  end

  def self.entry_of(colour) = colour.zero? ? nil : colour - COLOUR_OFFSET
end
