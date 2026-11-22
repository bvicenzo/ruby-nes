# frozen_string_literal: true

# The priority multiplexer (https://www.nesdev.org/wiki/PPU_rendering): "This selection depends on whether each pixel is
# transparent (low 2 bits are both 0) and the sprite's priority"; where both are opaque, its decision table gives the
# sprite with priority 0 and the background with priority 1. The renderer draws a lone opaque layer itself and asks the
# multiplexer only where both pixels are opaque (plan 25, decision 7). A sprite entry carries bit 5 for "behind
# background" and bit 6 for sprite 0 (SpriteLine); the drawn entry is its 5-bit palette entry. Sprite 0 hit needs "an
# opaque pixel of sprite 0" over "an opaque pixel of the background", "regardless of sprite priority"
# (https://www.nesdev.org/wiki/PPU_OAM), so SpriteZeroHit is asked on every such pixel.
RSpec.describe Ruby::Nes::Ppu::PriorityMultiplexer do
  describe '#palette_entry' do
    subject(:multiplexer) { described_class.new(sprite_zero_hit:) }

    let(:sprite_zero_hit) { instance_double(Ruby::Nes::Ppu::SpriteZeroHit, check: nil) }

    context 'when the sprite is behind the background' do
      it "is the background's entry" do
        expect(multiplexer.palette_entry(100, 0x0B, 0x75)).to eq(0x0B)
      end

      it 'checks for a sprite 0 hit' do
        multiplexer.palette_entry(100, 0x0B, 0x75)
        expect(sprite_zero_hit).to have_received(:check).with(100, 0x75)
      end
    end

    context 'when the sprite is in front' do
      it "is the sprite's palette entry, without its flags" do
        expect(multiplexer.palette_entry(100, 0x0B, 0x55)).to eq(0x15)
      end

      it 'checks for a sprite 0 hit' do
        multiplexer.palette_entry(100, 0x0B, 0x55)
        expect(sprite_zero_hit).to have_received(:check).with(100, 0x55)
      end
    end
  end
end
