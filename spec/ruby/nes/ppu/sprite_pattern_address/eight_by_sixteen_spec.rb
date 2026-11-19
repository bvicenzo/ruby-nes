# frozen_string_literal: true

# 8×16 sprites (https://www.nesdev.org/wiki/PPU_OAM): "the PPU ignores the pattern table selection and selects a pattern
# table from bit 0 of this number"; the rest is the "Tile number of top of sprite (0 to 254; bottom half gets the next
# tile)" ($00 maps to $0000-$001F, $01 to $1000-$101F in the page's map); "In 8x16 mode, vertical flip flips each of
# the subtiles and also exchanges their position". A pattern address is "0HNNNN NNNNPyyy"
# (https://www.nesdev.org/wiki/PPU_pattern_tables). A row past the sprite, what an empty slot's $FF Y gives, keeps its
# low 4 bits: a derivation, the sprite has 16 rows.
RSpec.describe Ruby::Nes::Ppu::SpritePatternAddress::EightBySixteen do
  describe '#address' do
    subject(:pattern_address) { described_class.new }

    context 'when the tile number is even' do
      context 'and the row is in the top half' do
        context 'and the sprite is not flipped vertically' do
          it 'is the row of the top tile in the pattern table at $0000' do
            expect(pattern_address.address(0x2A, 3, 0x00)).to eq(0x02A3)
          end
        end

        context 'and the sprite is flipped vertically' do
          it 'is the mirrored row of the bottom tile' do
            expect(pattern_address.address(0x2A, 3, 0x80)).to eq(0x02B4)
          end
        end
      end

      context 'and the row is in the bottom half' do
        context 'and the sprite is not flipped vertically' do
          it 'is the row of the bottom tile' do
            expect(pattern_address.address(0x2A, 11, 0x00)).to eq(0x02B3)
          end
        end

        context 'and the sprite is flipped vertically' do
          it 'is the mirrored row of the top tile' do
            expect(pattern_address.address(0x2A, 11, 0x80)).to eq(0x02A4)
          end
        end
      end
    end

    context 'when the row is past the sprite' do
      it 'wraps within the sprite' do
        expect(pattern_address.address(0x2A, 0x6B, 0x00)).to eq(0x02B3)
      end
    end

    context 'when the tile number is odd' do
      it 'is the row of the top tile, the even number below, in the pattern table at $1000' do
        expect(pattern_address.address(0x2B, 3, 0x00)).to eq(0x12A3)
      end
    end
  end

  describe '#height' do
    subject(:pattern_address) { described_class.new }

    it 'is 16' do
      expect(pattern_address.height).to eq(16)
    end
  end
end
