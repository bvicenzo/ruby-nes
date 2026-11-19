# frozen_string_literal: true

# The background's shift registers (https://www.nesdev.org/wiki/PPU_rendering): pattern data goes into two 16-bit
# shift registers, attribute data through 1-bit latches into 8-bit ones (modelled as 16-bit registers whose new byte is
# the palette bit repeated, plan 13); "The shifters are reloaded during ticks 9, 17, 25, ..., 257", and each dot "a
# 4-bit pixel is selected by the fine x register" from them, "which are then shifted". Plane 0 gives the pixel's bit 0,
# plane 1 its bit 1 (https://www.nesdev.org/wiki/PPU_pattern_tables), the attribute's palette its bits 3-2
# (https://www.nesdev.org/wiki/PPU_palettes).
RSpec.describe Ruby::Nes::Ppu::BackgroundShifters do
  describe '#pixel' do
    # Bit 15 and bit 8 hold different pixels: plane 0 set, plane 1 clear, palette 2 at bit 15; the opposite at bit 8.
    subject(:shifters) do
      described_class.new(
        pattern_low: 0b10000000_00000000,
        pattern_high: 0b00000001_00000000,
        attribute_low: 0b00000001_00000000,
        attribute_high: 0b10000000_00000000
      )
    end

    context 'when fine X is 0' do
      it 'combines bit 15 of the pattern and attribute shifters' do
        expect(shifters.pixel(0)).to eq(0b10_01)
      end
    end

    context 'when fine X is 7' do
      it 'combines bit 8 of the pattern and attribute shifters' do
        expect(shifters.pixel(7)).to eq(0b01_10)
      end
    end
  end

  describe '#shift' do
    # Bit 15 is pixel 0, bit 14 is pixel 3 of palette 1.
    subject(:shifters) do
      described_class.new(
        pattern_low: 0b01000000_00000000,
        pattern_high: 0b01000000_00000000,
        attribute_low: 0b01000000_00000000,
        attribute_high: 0
      )
    end

    before { shifters.shift }

    it 'brings the next pixel under fine X' do
      expect(shifters.pixel(0)).to eq(0b01_11)
    end
  end

  describe '#reload' do
    context 'when no tile is queued' do
      # The tile on screen is all pixel 1 of palette 0.
      subject(:shifters) do
        described_class.new(pattern_low: 0b11111111_00000000, pattern_high: 0, attribute_low: 0, attribute_high: 0)
      end

      # The new tile starts with pixel 2 of palette 2.
      before { shifters.reload(0b00000000, 0b10000000, 0b10) }

      it 'keeps the tile on screen in the high byte' do
        expect(shifters.pixel(0)).to eq(0b00_01)
      end

      it 'queues the new tile 8 pixels behind it' do
        8.times { shifters.shift }
        expect(shifters.pixel(0)).to eq(0b10_10)
      end
    end

    context 'when a tile is still queued in the low byte' do
      # The queued tile is all pixel 3 of palette 1, as when rendering is turned on between two reloads.
      subject(:shifters) do
        described_class.new(
          pattern_low: 0b00000000_11111111,
          pattern_high: 0b00000000_11111111,
          attribute_low: 0b00000000_11111111,
          attribute_high: 0
        )
      end

      # The new tile starts with pixel 2 of palette 2.
      before { shifters.reload(0b00000000, 0b10000000, 0b10) }

      it 'replaces the queued tile with the new one' do
        8.times { shifters.shift }
        expect(shifters.pixel(0)).to eq(0b10_10)
      end
    end
  end
end
