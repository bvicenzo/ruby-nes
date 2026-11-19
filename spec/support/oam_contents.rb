# frozen_string_literal: true

# Builds a Ruby::Nes::Ppu::Oam whose 256 bytes are `fill`, except the bytes of the sprites given, each one an array of
# its first bytes (Y, tile, attributes, X) from byte 0; the bytes go in through OAMDATA writes, so byte 2 keeps only
# its implemented bits ($E3). The default fill, $F8, is the value blargg's sprite tests clear OAM with, out of range on
# every visible scanline as a Y ($F8) and as an attribute byte ($E0).
#
#   OamContents.build(9 => [0xF8, 100])  # sprite 9: Y $F8, tile 100
module OamContents
  FILL = 0xF8
  SPRITE_SIZE = Ruby::Nes::Ppu::Oam::SPRITE_SIZE

  def self.build(fill: FILL, **sprites)
    bytes = Array.new(Ruby::Nes::Ppu::Oam::SIZE, fill)
    sprites.each do |sprite, sprite_bytes|
      bytes[sprite * SPRITE_SIZE, sprite_bytes.size] = sprite_bytes
    end
    oam = Ruby::Nes::Ppu::Oam.new
    bytes.each { |byte| oam.write(byte) }
    oam
  end
end
