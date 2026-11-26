# frozen_string_literal: true

require 'ruby/nes/frontends/screens'

# The paused game's picture dimmed under a menu (plan 38, decision 4): each pixel's colour becomes the same hue one
# value (luma) row lower. A colour index is "VV HHHH", the value in bits 4-5 and the hue in bits 0-3; hues $E-$F are
# black, $0F the canonical black, and $0D, "blacker than black", is never used
# (https://www.nesdev.org/wiki/PPU_palettes). So the darkest row, the black hues and $1D become $0F. A pixel's emphasis
# bits, 6-8 (docs/architecture.md, Frame buffer contract), stay as they are. The frame given is left as it is.
RSpec.describe Ruby::Nes::Frontends::Screens::Shade do
  describe '.dim' do
    context 'when a pixel is of a black hue' do
      it 'is black' do
        expect(described_class.dim([0x2E, 0x3F])).to eq([0x0F, 0x0F])
      end
    end

    context 'when a pixel is of the darkest row' do
      it 'is black' do
        expect(described_class.dim([0x00, 0x0C])).to eq([0x0F, 0x0F])
      end
    end

    context 'when a pixel is of a brighter row' do
      context 'but it would dim to $0D' do
        it 'is black' do
          expect(described_class.dim([0x1D])).to eq([0x0F])
        end
      end

      context 'and it dims to another colour' do
        it 'is the same hue one row lower' do
          expect(described_class.dim([0x16, 0x2A, 0x3D])).to eq([0x06, 0x1A, 0x2D])
        end
      end
    end

    context 'when a pixel has emphasis bits' do
      it 'keeps them' do
        expect(described_class.dim([0x16 | 0x140, 0x0C | 0x80])).to eq([0x06 | 0x140, 0x0F | 0x80])
      end
    end

    context 'when the frame is dimmed' do
      subject(:game_frame) { [0x30, 0x16] }

      it 'leaves the frame given as it is' do
        described_class.dim(game_frame)

        expect(game_frame).to eq([0x30, 0x16])
      end
    end
  end
end
