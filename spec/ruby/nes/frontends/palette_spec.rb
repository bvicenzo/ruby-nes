# frozen_string_literal: true

require 'ruby/nes/frontends/palette'

# The colours of NESdev's 2C02G_U_wiki.pal (https://www.nesdev.org/wiki/File:2C02G_U_wiki.pal), all 1536 bytes: 64
# colours "when colour (de-)emphasis bits are applied" (https://www.nesdev.org/wiki/.pal) for each of the 8 emphasis
# combinations, in the order of the pixel's bits 8-6 (plan 16, Context). A pixel is a colour (bits 5-0) plus PPUMASK's
# emphasis bits moved to bits 6-8 (plan 16, decision 2).
RSpec.describe Ruby::Nes::Frontends::Palette do
  describe '.rgb' do
    context 'when a pixel is past 511' do
      let(:frame_buffer) { [0x30, 0x200] }

      it 'raises an argument error' do
        expect { described_class.rgb(frame_buffer) }.to raise_error(ArgumentError, /0-511/)
      end
    end

    context 'when every pixel is within 0-511' do
      context 'and no pixel has emphasis bits' do
        let(:frame_buffer) { [0x30, 0x01, 0x16] }

        it "returns each pixel's red, green and blue bytes, in order, as binary", :aggregate_failures do
          rgb = described_class.rgb(frame_buffer)
          expect(rgb).to eq(['FFFFFF000C8EA31800'].pack('H*'))
          expect(rgb.encoding).to eq(Encoding::BINARY)
        end
      end

      context 'and pixels have emphasis bits' do
        let(:frame_buffer) { [0x040, 0x0AC, 0x1F0, 0x1CF] }

        it 'returns the colours of their emphasis blocks' do
          expect(described_class.rgb(frame_buffer)).to eq(['593A320AB28CB8B8B8000000'].pack('H*'))
        end
      end
    end
  end
end
