# frozen_string_literal: true

# The picture the PPU draws: a frame buffer of 256 × 240 palette indices, row by row (docs/architecture.md, Frame
# buffer contract). A pixel's colour is the palette RAM entry at $3F00 plus its 5-bit index
# (https://www.nesdev.org/wiki/PPU_palettes); greyscale is "bitwise ANDing the color with $30"
# (https://www.nesdev.org/wiki/PPU_registers). In forced blank (rendering disabled) the PPU draws the backdrop, $3F00,
# "However, if the current VRAM address in v points into palette RAM ($3F00-$3FFF), then the color at that address will
# be drawn, instead" (https://www.nesdev.org/wiki/PPU_palettes, Backdrop override).
RSpec.describe Ruby::Nes::Ppu::Picture do
  describe '#draw' do
    let(:bus) { Ruby::Nes::PpuBus.new(mapper: instance_double(Ruby::Nes::Mappers::Nrom)) }

    before { bus.write(0x3F0D, 0x2C) }

    context 'when greyscale is off' do
      subject(:picture) { described_class.new(bus:) }

      before { picture.draw(17, 3, 0x0D) }

      it "stores the palette entry's colour at the pixel's place, row by row" do
        expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x2C)
      end
    end

    context 'when greyscale is on' do
      subject(:picture) { described_class.new(bus:, greyscale: true) }

      before { picture.draw(17, 3, 0x0D) }

      it "stores the colour's bits 5-4" do
        expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x20)
      end
    end
  end

  describe '#draw_forced_blank' do
    let(:bus) { Ruby::Nes::PpuBus.new(mapper: instance_double(Ruby::Nes::Mappers::Nrom)) }

    before do
      bus.write(0x3F00, 0x0F)
      bus.write(0x3F05, 0x2C)
    end

    context 'when v points below the palette' do
      subject(:picture) { described_class.new(bus:) }

      before { picture.draw_forced_blank(17, 3, 0x3EFF) }

      it 'stores the backdrop colour' do
        expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x0F)
      end
    end

    context 'when v points into the palette' do
      context 'and its fifteenth bit is clear' do
        subject(:picture) { described_class.new(bus:) }

        before { picture.draw_forced_blank(17, 3, 0x3F05) }

        it 'stores the colour at v' do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x2C)
        end
      end

      context 'and its fifteenth bit is set' do
        subject(:picture) { described_class.new(bus:) }

        before { picture.draw_forced_blank(17, 3, 0x7F05) }

        it 'stores the colour at the low 14 bits of v' do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x2C)
        end
      end

      context 'and greyscale is on' do
        subject(:picture) { described_class.new(bus:, greyscale: true) }

        before { picture.draw_forced_blank(17, 3, 0x3F05) }

        it "stores the colour's bits 5-4" do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x20)
        end
      end
    end
  end
end
