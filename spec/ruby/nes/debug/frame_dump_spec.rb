# frozen_string_literal: true

# A frame as a binary PPM image (https://netpbm.sourceforge.net/doc/ppm.html): "P6", the width and height, the maximum
# colour value 255, then each pixel's red, green and blue bytes, row by row. Each palette index (0-63) becomes its
# colour in NESdev's 2C02G_U_wiki.pal (plan 13, decision 2). The frame buffer comes from the PPU, so an index outside
# 0-63 is a bug and fails loudly.
RSpec.describe Ruby::Nes::Debug::FrameDump do
  describe '.ppm' do
    context 'when every index is a palette colour' do
      let(:frame_buffer) { [0x30, 0x01] + Array.new((256 * 240) - 3, 0x0F) + [0x16] }

      it 'is the P6 header of a 256 × 240 image followed by each colour, row by row', :aggregate_failures do
        image = described_class.ppm(frame_buffer)
        header = "P6\n256 240\n255\n"
        expect(image.byteslice(0, header.bytesize)).to eq(header)
        expect(image.bytesize).to eq(header.bytesize + (256 * 240 * 3))
        expect(image.byteslice(header.bytesize, 9).bytes).to eq([0xFF, 0xFF, 0xFF, 0x00, 0x0C, 0x8E, 0x00, 0x00, 0x00])
        expect(image.byteslice(-3, 3).bytes).to eq([0xA3, 0x18, 0x00])
      end
    end

    context 'when an index is outside 0-63' do
      let(:frame_buffer) { Array.new(256 * 240, 0x40) }

      it 'raises an index error' do
        expect { described_class.ppm(frame_buffer) }.to raise_error(IndexError)
      end
    end
  end
end
