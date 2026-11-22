# frozen_string_literal: true

# The sprites of a scanline "get drawn front (lower index) to back (higher index) into a buffer, taking only the first
# opaque pixel that matches each X coordinate. Priority does not affect ordering in this buffer but is saved with each
# pixel" (https://www.nesdev.org/wiki/PPU_sprite_priority). A sprite's row is two pattern bytes, bit 7 the leftmost
# pixel, plane 0 bit 0 and plane 1 bit 1 of its value (https://www.nesdev.org/wiki/PPU_pattern_tables); value 0 is
# transparent. Its palette entry is $10 | palette << 2 | value, "Palette (4 to 7)" being attribute bits 1-0
# (https://www.nesdev.org/wiki/PPU_OAM, https://www.nesdev.org/wiki/PPU_palettes); attribute bit 5 is "Priority (0: in
# front of background; 1: behind background)", bit 6 "Flip sprite horizontally"; "X-scroll values of $F9-FF results in
# parts of the sprite to be past the right edge of the screen, thus invisible". An entry carries bit 5 for a pixel
# behind the background and bit 6 for a pixel of sprite 0; 0 is an empty column.
RSpec.describe Ruby::Nes::Ppu::SpriteLine do
  describe '#place' do
    subject(:line) { described_class.new }

    context 'when the columns are free' do
      before { line.place(100, 0b1010_0000, 0b0110_0000, 0x02, false) }

      it "puts each opaque pixel of the row at its column with the sprite's palette entry", :aggregate_failures do
        expect(line.entries[100]).to eq(0x19)
        expect(line.entries[101]).to eq(0x1A)
        expect(line.entries[102]).to eq(0x1B)
      end

      it 'leaves the columns of transparent pixels empty', :aggregate_failures do
        expect(line.entries[103]).to eq(0x00)
        expect(line.entries[107]).to eq(0x00)
      end
    end

    context 'when an earlier sprite left an opaque pixel at a column' do
      before do
        line.place(100, 0b1000_0000, 0b0000_0000, 0x00, false)
        line.place(100, 0b1000_0000, 0b1000_0000, 0x01, false)
      end

      it 'keeps the earlier pixel' do
        expect(line.entries[100]).to eq(0x11)
      end
    end

    context 'when an earlier sprite left a column transparent' do
      before do
        line.place(100, 0b0000_0000, 0b0000_0000, 0x00, false)
        line.place(100, 0b1000_0000, 0b0000_0000, 0x01, false)
      end

      it 'puts the pixel' do
        expect(line.entries[100]).to eq(0x15)
      end
    end

    context 'when the sprite runs past the right edge' do
      before { line.place(252, 0b1111_1111, 0b0000_0000, 0x00, false) }

      it 'puts only the columns up to 255', :aggregate_failures do
        expect(line.entries[252]).to eq(0x11)
        expect(line.entries[255]).to eq(0x11)
        expect(line.entries[256]).to be_nil
      end
    end

    context 'when the sprite is flipped horizontally' do
      before { line.place(100, 0b1010_0000, 0b0110_0000, 0x42, false) }

      it 'puts the row mirrored', :aggregate_failures do
        expect(line.entries[107]).to eq(0x19)
        expect(line.entries[106]).to eq(0x1A)
        expect(line.entries[105]).to eq(0x1B)
        expect(line.entries[100]).to eq(0x00)
      end
    end

    context 'when the sprite is behind the background' do
      before { line.place(100, 0b1000_0000, 0b0000_0000, 0x20, false) }

      it 'marks its pixels behind the background' do
        expect(line.entries[100]).to eq(0x31)
      end
    end

    context 'when the sprite is sprite 0' do
      before { line.place(100, 0b1000_0000, 0b0000_0000, 0x00, true) }

      it 'marks its pixels as sprite 0' do
        expect(line.entries[100]).to eq(0x51)
      end
    end
  end

  describe '#clear' do
    subject(:line) { described_class.new }

    before { line.place(100, 0b1000_0000, 0b0000_0000, 0x00, true) }

    it 'empties every column' do
      expect { line.clear }.to change { line.entries[100] }.from(0x51).to(0x00)
    end
  end

  # The renderer keeps a reference to the entries across scanlines (plan 25, decision 7).
  describe '#entries' do
    context 'when nothing was placed' do
      subject(:line) { described_class.new }

      it 'is 256 empty entries' do
        expect(line.entries).to eq(Array.new(256, 0))
      end
    end

    context 'when a sprite was placed' do
      subject(:line) { described_class.new }

      before { line.place(100, 0b1000_0001, 0b0000_0000, 0x00, false) }

      it "holds its pixels' entries at their columns", :aggregate_failures do
        expect(line.entries[100]).to eq(0x11)
        expect(line.entries[107]).to eq(0x11)
        expect(line.entries.count(&:positive?)).to eq(2)
      end
    end

    context 'when the line is cleared' do
      subject(:line) { described_class.new }

      before { line.place(100, 0b1000_0000, 0b0000_0000, 0x00, false) }

      it 'stays the same array' do
        expect { line.clear }.not_to(change { line.entries.object_id })
      end
    end
  end
end
