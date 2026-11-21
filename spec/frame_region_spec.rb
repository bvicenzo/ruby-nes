# frozen_string_literal: true

# A band of rows of a 256-pixel-wide frame, optionally without a rectangle.
RSpec.describe FrameRegion do
  describe '#pixels' do
    # Three rows whose pixels hold their own index in the frame.
    let(:frame) { Array.new(256 * 3) { |index| index } }

    context 'when the region has no hole' do
      subject(:region) { described_class.new(rows: 1..2) }

      it "returns its rows' pixels in order" do
        expect(region.pixels(frame)).to eq((256...768).to_a)
      end
    end

    context 'when the region has a hole' do
      context 'and a row crosses the hole' do
        subject(:region) { described_class.new(rows: 1..1, hole_rows: 1..1, hole_columns: 2..253) }

        it "leaves the hole's columns out" do
          expect(region.pixels(frame)).to eq([256, 257, 510, 511])
        end
      end

      context 'and a row is outside the hole' do
        subject(:region) { described_class.new(rows: 0..0, hole_rows: 1..1, hole_columns: 2..253) }

        it 'keeps the whole row' do
          expect(region.pixels(frame)).to eq((0...256).to_a)
        end
      end
    end
  end
end
