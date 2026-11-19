# frozen_string_literal: true

# Secondary OAM (https://www.nesdev.org/wiki/PPU_sprite_evaluation): the "32-byte buffer for current sprites on
# scanline", 8 sprites of 4 bytes (Y, tile, attributes, X), "initialized to $FF" before each evaluation; the sprites
# the evaluation selects go into "the next open slot". Whether sprite 0 is among them is kept apart: the PPU uses a flag
# "to keep track of whether sprite 0 occurs on the _next_ scanline", and sprite 0, "when it is within y range for the
# next scanline, always gets assigned the first sprite output unit" (https://www.nesdev.org/wiki/PPU_OAM): slot 0.
RSpec.describe Ruby::Nes::Ppu::SecondaryOam do
  describe '.new' do
    it 'holds no sprite, every byte $FF, sprite 0 unselected', :aggregate_failures do
      secondary_oam = described_class.new
      expect(secondary_oam.count).to eq(0)
      expect(secondary_oam.y_position(7)).to eq(0xFF)
      expect(secondary_oam.tile(7)).to eq(0xFF)
      expect(secondary_oam.attributes(7)).to eq(0xFF)
      expect(secondary_oam.x_position(7)).to eq(0xFF)
      expect(secondary_oam).not_to be_sprite_zero(0)
    end
  end

  describe '#add' do
    subject(:secondary_oam) { described_class.new }

    context 'when it holds no sprite' do
      before { secondary_oam.add(0x10, 0x21, 0x43, 0x80) }

      it 'puts the four bytes in slot 0 and counts one sprite', :aggregate_failures do
        expect(secondary_oam.y_position(0)).to eq(0x10)
        expect(secondary_oam.tile(0)).to eq(0x21)
        expect(secondary_oam.attributes(0)).to eq(0x43)
        expect(secondary_oam.x_position(0)).to eq(0x80)
        expect(secondary_oam.count).to eq(1)
      end
    end

    context 'when it holds sprites' do
      before do
        secondary_oam.add(0x10, 0x21, 0x43, 0x80)
        secondary_oam.add(0x12, 0x34, 0x01, 0x90)
      end

      it 'puts the four bytes in the next slot', :aggregate_failures do
        expect(secondary_oam.y_position(1)).to eq(0x12)
        expect(secondary_oam.tile(1)).to eq(0x34)
        expect(secondary_oam.attributes(1)).to eq(0x01)
        expect(secondary_oam.x_position(1)).to eq(0x90)
        expect(secondary_oam.count).to eq(2)
      end
    end
  end

  describe '#sprite_zero?' do
    subject(:secondary_oam) { described_class.new }

    context 'when sprite 0 is not selected' do
      context 'and the slot is 0' do
        it 'is false' do
          expect(secondary_oam).not_to be_sprite_zero(0)
        end
      end
    end

    context 'when sprite 0 is selected' do
      before { secondary_oam.select_sprite_zero }

      context 'but the slot is not 0' do
        it 'is false' do
          expect(secondary_oam).not_to be_sprite_zero(1)
        end
      end

      context 'and the slot is 0' do
        it 'is true' do
          expect(secondary_oam).to be_sprite_zero(0)
        end
      end
    end
  end

  describe '#clear' do
    subject(:secondary_oam) { described_class.new }

    before do
      secondary_oam.add(0x10, 0x21, 0x43, 0x80)
      secondary_oam.select_sprite_zero
    end

    it 'empties it: no sprite, every byte $FF, sprite 0 unselected', :aggregate_failures do
      secondary_oam.clear
      expect(secondary_oam.count).to eq(0)
      expect(secondary_oam.y_position(0)).to eq(0xFF)
      expect(secondary_oam.tile(0)).to eq(0xFF)
      expect(secondary_oam.attributes(0)).to eq(0xFF)
      expect(secondary_oam.x_position(0)).to eq(0xFF)
      expect(secondary_oam).not_to be_sprite_zero(0)
    end
  end
end
