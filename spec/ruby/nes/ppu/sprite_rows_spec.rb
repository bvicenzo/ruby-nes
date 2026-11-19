# frozen_string_literal: true

# A sprite's Y is "delayed by one scanline" (https://www.nesdev.org/wiki/PPU_OAM) and the evaluation on a scanline
# selects the sprites of the next one (https://www.nesdev.org/wiki/PPU_sprite_evaluation), so a sprite is "in range"
# on the scanlines Y to Y + height - 1: a derivation, the page gives no formula (plan 14).
RSpec.describe Ruby::Nes::Ppu::SpriteRows do
  describe '.in_range?' do
    context 'when the scanline is above the sprite top' do
      it 'is false' do
        expect(described_class).not_to be_in_range(100, 99, 16)
      end
    end

    context 'when the scanline is the sprite top row' do
      it 'is true' do
        expect(described_class).to be_in_range(100, 100, 16)
      end
    end

    context 'when the scanline is the sprite bottom row' do
      it 'is true' do
        expect(described_class).to be_in_range(100, 115, 16)
      end
    end

    context 'when the scanline is below the sprite bottom row' do
      it 'is false' do
        expect(described_class).not_to be_in_range(100, 116, 16)
      end
    end
  end
end
