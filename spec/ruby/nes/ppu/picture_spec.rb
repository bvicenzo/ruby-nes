# frozen_string_literal: true

# The picture the PPU draws: a frame buffer of 256 × 240 pixels, row by row (docs/architecture.md, Frame buffer
# contract). A pixel's colour is the palette RAM entry at $3F00 plus its 5-bit index
# (https://www.nesdev.org/wiki/PPU_palettes); greyscale is "bitwise ANDing the color with $30"
# (https://www.nesdev.org/wiki/PPU_registers). In forced blank (rendering disabled) the PPU draws the backdrop, $3F00,
# "However, if the current VRAM address in v points into palette RAM ($3F00-$3FFF), then the color at that address will
# be drawn, instead" (https://www.nesdev.org/wiki/PPU_palettes, Backdrop override). The emphasis bits, PPUMASK bits 5-7,
# go to the pixel's bits 6-8 (plan 16, decision 2); they "are applied independently of greyscale"
# (https://www.nesdev.org/wiki/Colour_emphasis). The pixels drawn reach the frame buffer when the frame is completed
# (plan 16, decision 1). The picture keeps each palette entry's final pixel value, rebuilt whenever palette RAM (which
# tells it of every write), greyscale or emphasis change, and hands it and the buffer it draws into to the renderer
# (plan 30, decisions 1 and 4).
RSpec.describe Ruby::Nes::Ppu::Picture do
  describe '#draw' do
    let(:palette_ram) { Ruby::Nes::PpuBus::PaletteRam.new }

    before { palette_ram.write(0x3F0D, 0x2C) }

    context 'when greyscale is off' do
      context 'and no colour is emphasized' do
        subject(:picture) { described_class.new(palette_ram:) }

        before do
          picture.draw(17, 3, 0x0D)
          picture.complete_frame
        end

        it "stores the palette entry's colour at the pixel's place, row by row" do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x2C)
        end
      end

      context 'and red and blue are emphasized' do
        subject(:picture) { described_class.new(palette_ram:, emphasis: 0xA0) }

        before do
          picture.draw(17, 3, 0x0D)
          picture.complete_frame
        end

        it 'stores the colour with the emphasis in bits 6-8' do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x16C)
        end
      end
    end

    context 'when greyscale is on' do
      context 'and no colour is emphasized' do
        subject(:picture) { described_class.new(palette_ram:, greyscale: true) }

        before do
          picture.draw(17, 3, 0x0D)
          picture.complete_frame
        end

        it "stores the colour's bits 5-4" do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x20)
        end
      end

      context 'and green is emphasized' do
        subject(:picture) { described_class.new(palette_ram:, greyscale: true, emphasis: 0x40) }

        before do
          picture.draw(17, 3, 0x0D)
          picture.complete_frame
        end

        it "stores the colour's bits 5-4 with the emphasis in bits 6-8" do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0xA0)
        end
      end
    end
  end

  describe '#draw_forced_blank' do
    let(:palette_ram) { Ruby::Nes::PpuBus::PaletteRam.new }

    before do
      palette_ram.write(0x3F00, 0x0F)
      palette_ram.write(0x3F05, 0x2C)
    end

    context 'when v points below the palette' do
      context 'and no colour is emphasized' do
        subject(:picture) { described_class.new(palette_ram:) }

        before do
          picture.draw_forced_blank(17, 3, 0x3EFF)
          picture.complete_frame
        end

        it 'stores the backdrop colour' do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x0F)
        end
      end

      context 'and blue is emphasized' do
        subject(:picture) { described_class.new(palette_ram:, emphasis: 0x80) }

        before do
          picture.draw_forced_blank(17, 3, 0x3EFF)
          picture.complete_frame
        end

        it 'stores the backdrop colour with the emphasis in bits 6-8' do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x10F)
        end
      end
    end

    context 'when v points into the palette' do
      context 'and its fifteenth bit is clear' do
        subject(:picture) { described_class.new(palette_ram:) }

        before do
          picture.draw_forced_blank(17, 3, 0x3F05)
          picture.complete_frame
        end

        it 'stores the colour at v' do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x2C)
        end
      end

      context 'and its fifteenth bit is set' do
        subject(:picture) { described_class.new(palette_ram:) }

        before do
          picture.draw_forced_blank(17, 3, 0x7F05)
          picture.complete_frame
        end

        it 'stores the colour at the low 14 bits of v' do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x2C)
        end
      end

      context 'and greyscale is on' do
        subject(:picture) { described_class.new(palette_ram:, greyscale: true) }

        before do
          picture.draw_forced_blank(17, 3, 0x3F05)
          picture.complete_frame
        end

        it "stores the colour's bits 5-4" do
          expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x20)
        end
      end
    end
  end

  describe '#colours' do
    let(:palette_ram) { Ruby::Nes::PpuBus::PaletteRam.new }

    context 'when palette RAM is written after the picture was built' do
      subject(:picture) { described_class.new(palette_ram:, greyscale: true, emphasis: 0x20) }

      before do
        picture
        palette_ram.write(0x3F0D, 0x2C)
      end

      it 'holds the new colour at its entry, greyscale and emphasis applied' do
        expect(picture.colours[0x0D]).to eq(0x60)
      end
    end

    context 'when the entry is entry 0 of a sprite palette' do
      subject(:picture) { described_class.new(palette_ram:) }

      before { palette_ram.write(0x3F04, 0x16) }

      it 'holds the colour of entry 0 of the background palette 16 entries below' do
        expect(picture.colours[0x14]).to eq(0x16)
      end
    end

    context 'when a colour changes' do
      subject(:picture) { described_class.new(palette_ram:) }

      it 'stays the same array' do
        expect { palette_ram.write(0x3F0D, 0x2C) }.not_to(change { picture.colours.object_id })
      end
    end
  end

  describe '#drawn_frame' do
    subject(:picture) { described_class.new(palette_ram:) }

    let(:palette_ram) { Ruby::Nes::PpuBus::PaletteRam.new }

    before { palette_ram.write(0x3F0D, 0x2C) }

    context 'when no frame was completed' do
      before { picture.draw(17, 3, 0x0D) }

      it 'holds the pixels drawn' do
        expect(picture.drawn_frame[(3 * 256) + 17]).to eq(0x2C)
      end
    end

    context 'when a frame was completed' do
      let!(:frame_buffer_before_the_completion) { picture.frame_buffer }

      before { picture.complete_frame }

      it 'is the buffer published before the completion' do
        expect(picture.drawn_frame).to be(frame_buffer_before_the_completion)
      end
    end
  end

  describe '#greyscale=' do
    let(:palette_ram) { Ruby::Nes::PpuBus::PaletteRam.new }

    before { palette_ram.write(0x3F0D, 0x2C) }

    context 'when greyscale is turned on' do
      subject(:picture) { described_class.new(palette_ram:) }

      before { picture.draw(16, 3, 0x0D) }

      it 'greys the pixels drawn after it only', :aggregate_failures do
        picture.greyscale = true
        picture.draw(17, 3, 0x0D)
        picture.complete_frame
        expect(picture.frame_buffer[(3 * 256) + 16]).to eq(0x2C)
        expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x20)
      end
    end

    context 'when greyscale is turned off' do
      subject(:picture) { described_class.new(palette_ram:, greyscale: true) }

      before { picture.draw(16, 3, 0x0D) }

      it 'draws the whole colour of the pixels drawn after it only', :aggregate_failures do
        picture.greyscale = false
        picture.draw(17, 3, 0x0D)
        picture.complete_frame
        expect(picture.frame_buffer[(3 * 256) + 16]).to eq(0x20)
        expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x2C)
      end
    end
  end

  describe '#emphasis=' do
    subject(:picture) { described_class.new(palette_ram:, emphasis: 0xE0) }

    let(:palette_ram) { Ruby::Nes::PpuBus::PaletteRam.new }

    before do
      palette_ram.write(0x3F0D, 0x2C)
      picture.draw(16, 3, 0x0D)
    end

    it 'emphasizes the pixels drawn after it only', :aggregate_failures do
      picture.emphasis = 0x20
      picture.draw(17, 3, 0x0D)
      picture.complete_frame
      expect(picture.frame_buffer[(3 * 256) + 16]).to eq(0x1EC)
      expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x6C)
    end
  end

  describe '#complete_frame' do
    subject(:picture) { described_class.new(palette_ram:) }

    let(:palette_ram) { Ruby::Nes::PpuBus::PaletteRam.new }

    before do
      palette_ram.write(0x3F0D, 0x2C)
      palette_ram.write(0x3F0E, 0x16)
    end

    context 'when pixels were drawn since the last completion' do
      before do
        picture.draw(17, 3, 0x0D)
        picture.complete_frame
      end

      it 'publishes them in the frame buffer' do
        expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x2C)
      end
    end

    context 'when pixels are drawn after the completion' do
      before do
        picture.draw(17, 3, 0x0D)
        picture.complete_frame
        picture.draw(17, 3, 0x0E)
      end

      it 'keeps them out of the frame buffer until the next completion' do
        expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x2C)
      end
    end

    context 'when the frame after them is completed too' do
      before do
        picture.draw(17, 3, 0x0D)
        picture.complete_frame
        picture.draw(17, 3, 0x0E)
        picture.complete_frame
      end

      it 'publishes the newer frame' do
        expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x16)
      end
    end
  end
end
