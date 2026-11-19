# frozen_string_literal: true

# 8×8 sprites (https://www.nesdev.org/wiki/PPU_OAM): byte 1 "is the tile number of this sprite within the pattern table
# selected in bit 3 of PPUCTRL"; attribute bit 7 is "Flip sprite vertically". A pattern address is "0HNNNN NNNNPyyy":
# table half, tile number, bit plane 0 and fine Y (https://www.nesdev.org/wiki/PPU_pattern_tables). A row past the
# tile, what an empty slot's $FF Y gives, keeps its low 3 bits: a derivation, the address has 3 bits of fine Y.
RSpec.describe Ruby::Nes::Ppu::SpritePatternAddress::EightByEight do
  describe '#address' do
    subject(:pattern_address) { described_class.new(pattern_table: 0x1000) }

    context 'when the sprite is not flipped vertically' do
      it 'is the row of the tile in the pattern table' do
        expect(pattern_address.address(0x2A, 3, 0x00)).to eq(0x12A3)
      end
    end

    context 'when the sprite is flipped vertically' do
      it 'is the mirrored row of the tile' do
        expect(pattern_address.address(0x2A, 3, 0x80)).to eq(0x12A4)
      end
    end

    context 'when the row is past the tile' do
      it 'wraps within the tile' do
        expect(pattern_address.address(0x2A, 0x6B, 0x00)).to eq(0x12A3)
      end
    end
  end

  describe '#height' do
    subject(:pattern_address) { described_class.new(pattern_table: 0x1000) }

    it 'is 8' do
      expect(pattern_address.height).to eq(8)
    end
  end
end
