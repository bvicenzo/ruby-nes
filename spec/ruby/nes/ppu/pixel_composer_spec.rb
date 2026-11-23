# frozen_string_literal: true

# The pixel composer draws the renderer's pixels into the picture's drawn frame, through the picture's colour of each
# palette entry (plan 30, decisions 1 and 6), at row y and column x of the 256-pixel rows. A background entry is 4 bits,
# 0 when transparent; a sprite line entry carries SpriteLine's flags, 0 where no sprite covers the column. Where only
# one layer is opaque its entry is drawn, a sprite's without its priority and sprite 0 marks; where both are, the
# priority multiplexer decides (https://www.nesdev.org/wiki/PPU_sprite_priority). A whole tile is 8 background entries
# in 32 bits, pixel i in bits 31 - 4i to 28 - 4i, composed with the sprite line from column x on and drawn from its
# index in the frame, row × 256 + x.
RSpec.describe Ruby::Nes::Ppu::PixelComposer do
  describe '#draw_pixel' do
    subject(:composer) { described_class.new(picture:, sprite_entries: Array.new(256, 0), multiplexer:) }

    let(:picture) { PaletteEntryPicture.build }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer, palette_entry: 0x15) }

    context 'when the sprite entry is empty' do
      context 'and the background is transparent' do
        before { composer.draw_pixel(0x00, 0x00, 17, 3) }

        it 'draws the backdrop entry' do
          expect(PaletteEntryPicture.entries(picture, row: 3, columns: [17])).to eq([0x00])
        end
      end

      context 'and the background is opaque' do
        before { composer.draw_pixel(0x09, 0x00, 17, 3) }

        it "draws the background's entry" do
          expect(PaletteEntryPicture.entries(picture, row: 3, columns: [17])).to eq([0x09])
        end
      end
    end

    # The sprite entry is palette 7 with pattern 01 ($1D), behind the background and sprite 0 ($7D).
    context 'when the sprite entry is opaque' do
      context 'and the background is transparent' do
        before { composer.draw_pixel(0x00, 0x7D, 17, 3) }

        it "draws the sprite's entry without its marks" do
          expect(PaletteEntryPicture.entries(picture, row: 3, columns: [17])).to eq([0x1D])
        end
      end

      context 'and the background is opaque' do
        before { composer.draw_pixel(0x09, 0x7D, 17, 3) }

        it "draws the priority multiplexer's entry, asking it with the column and both entries", :aggregate_failures do
          expect(PaletteEntryPicture.entries(picture, row: 3, columns: [17])).to eq([0x15])
          expect(multiplexer).to have_received(:palette_entry).with(17, 0x09, 0x7D)
        end
      end
    end
  end

  describe '#draw_tile' do
    subject(:composer) { described_class.new(picture:, sprite_entries:, multiplexer:) }

    let(:picture) { PaletteEntryPicture.build }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer, palette_entry: 0x15) }

    context 'when no sprite covers the tile' do
      let(:sprite_entries) { Array.new(256, 0) }

      before { composer.draw_tile(0x0123_4567, 16, (3 * 256) + 16) }

      it 'draws pixel i of the tile at column x + i' do
        expect(PaletteEntryPicture.entries(picture, row: 3, columns: 16..23))
          .to eq([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
      end
    end

    # The sprite line's entries over the tile are palette 7 with pattern 01, behind the background and sprite 0 ($7D).
    context 'when only the sprites are opaque' do
      let(:sprite_entries) { Array.new(256, 0).fill(0x7D, 16, 8) }

      before { composer.draw_tile(0x0000_0000, 16, (3 * 256) + 16) }

      it "draws the sprites' entries without their marks" do
        expect(PaletteEntryPicture.entries(picture, row: 3, columns: 16..23)).to eq([0x1D] * 8)
      end
    end

    context 'when both layers are opaque' do
      let(:sprite_entries) { Array.new(256, 0).fill(0x7D, 16, 8) }

      before { composer.draw_tile(0x9999_9999, 16, (3 * 256) + 16) }

      it "draws the priority multiplexer's entries, asking it with each column and both entries", :aggregate_failures do
        expect(PaletteEntryPicture.entries(picture, row: 3, columns: 16..23)).to eq([0x15] * 8)
        expect(multiplexer).to have_received(:palette_entry).with(16, 0x09, 0x7D).once
        expect(multiplexer).to have_received(:palette_entry).with(23, 0x09, 0x7D).once
        expect(multiplexer).to have_received(:palette_entry).exactly(8).times
      end
    end
  end

  describe '#draw_background_tile' do
    subject(:composer) { described_class.new(picture:, sprite_entries:, multiplexer:) }

    let(:picture) { PaletteEntryPicture.build }
    let(:sprite_entries) { Array.new(256, 0x7D) }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    before { composer.draw_background_tile(0x0123_4567, (3 * 256) + 16) }

    it 'draws pixel i of the tile at column x + i, whatever the sprite line holds' do
      expect(PaletteEntryPicture.entries(picture, row: 3, columns: 16..23))
        .to eq([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
    end
  end

  describe '#complete_picture' do
    subject(:composer) { described_class.new(picture:, sprite_entries: Array.new(256, 0), multiplexer:) }

    let(:picture) { PaletteEntryPicture.build }
    let(:multiplexer) { instance_double(Ruby::Nes::Ppu::PriorityMultiplexer) }

    before do
      composer.draw_pixel(0x09, 0x00, 17, 3)
      composer.complete_picture
      composer.draw_pixel(0x05, 0x00, 17, 4)
    end

    it 'publishes the frame drawn' do
      expect(picture.frame_buffer[(3 * 256) + 17]).to eq(0x09 + PaletteEntryPicture::COLOUR_OFFSET)
    end

    it "draws the next pixels into the picture's new drawn frame" do
      expect(PaletteEntryPicture.entries(picture, row: 4, columns: [17])).to eq([0x05])
    end
  end
end
