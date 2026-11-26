# frozen_string_literal: true

require 'zlib'
require 'ruby/nes/frontends/screenshot'

# A frame as a PNG image (plan 16; plan 35, decision 7): the headless frontend's screenshots and the save states'
# pictures. The picture's 256 × 240 pixels in the palette's colours (Frontends::Palette). The image is read back here
# by its layout (https://www.w3.org/TR/png-3/): the 8-byte signature, then IHDR (length, type, width, height…) at byte
# 8, then IDAT, whose data starts at byte 41 and inflates to each row's filter byte followed by its RGB bytes.
RSpec.describe Ruby::Nes::Frontends::Screenshot do
  describe '.png' do
    # Every pixel is $30 (white) with red emphasis, palette index $130.
    let(:frame_buffer) { Array.new(Ruby::Nes::Ppu::Picture::WIDTH * Ruby::Nes::Ppu::Picture::HEIGHT, 0x130) }
    let(:png) { described_class.png(frame_buffer) }
    let(:image_data) { Zlib::Inflate.inflate(png.byteslice(41, png.byteslice(33, 4).unpack1('N'))) }

    it "is a PNG image of the picture's size, in the palette's colours", :aggregate_failures do
      expect(png.byteslice(0, 8)).to eq("\x89PNG\r\n\x1A\n".b)
      expect(png.byteslice(16, 8).unpack('NN')).to eq([256, 240])
      expect(image_data.byteslice(1, 3)).to eq(Ruby::Nes::Frontends::Palette::COLOURS[0x130])
    end
  end
end
