# frozen_string_literal: true

require 'ruby/nes/frontends/viewport'

# The part of the frame a window shows and the window's size (plan 18, decision 4). The scale is an integer; pixels
# are square or 8:7 wide, "the pixel aspect ratio on a 4:3 TV"; cropping the overscan shows lines 8 to 231, as
# "Emulators and LCD HDTVs tend to use" (https://www.nesdev.org/wiki/Overscan).
RSpec.describe Ruby::Nes::Frontends::Viewport do
  describe '#source' do
    context 'when the overscan is shown' do
      subject(:viewport) { described_class.new(scale: 2, pixel_aspect: 1, crop_overscan: false) }

      it 'is the whole frame' do
        expect(viewport.source).to have_attributes(x: 0, y: 0, width: 256, height: 240)
      end
    end

    context 'when the overscan is cropped' do
      subject(:viewport) { described_class.new(scale: 2, pixel_aspect: 1, crop_overscan: true) }

      it 'skips the top and bottom 8 lines' do
        expect(viewport.source).to have_attributes(x: 0, y: 8, width: 256, height: 224)
      end
    end
  end

  describe '#width' do
    context 'when pixels are square' do
      subject(:viewport) { described_class.new(scale: 3, pixel_aspect: 1, crop_overscan: false) }

      it 'is the frame width times the scale' do
        expect(viewport.width).to eq(768)
      end
    end

    context 'when pixels are 8:7' do
      subject(:viewport) { described_class.new(scale: 3, pixel_aspect: Rational(8, 7), crop_overscan: false) }

      it 'is the frame width times the scale stretched by 8/7, rounded' do
        expect(viewport.width).to eq(878)
      end
    end
  end

  describe '#height' do
    context 'when the overscan is shown' do
      subject(:viewport) { described_class.new(scale: 3, pixel_aspect: 1, crop_overscan: false) }

      it 'is 240 lines times the scale' do
        expect(viewport.height).to eq(720)
      end
    end

    context 'when the overscan is cropped' do
      subject(:viewport) { described_class.new(scale: 3, pixel_aspect: 1, crop_overscan: true) }

      it 'is 224 lines times the scale' do
        expect(viewport.height).to eq(672)
      end
    end
  end
end
