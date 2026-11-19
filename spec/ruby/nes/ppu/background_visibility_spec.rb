# frozen_string_literal: true

# Which background pixels show (https://www.nesdev.org/wiki/PPU_registers, PPUMASK): bit 3 "Enable background
# rendering"; bit 1 "Show background in leftmost 8 pixels of screen, 0: Hide", hiding them "making them transparent and
# thus drawing the backdrop color there". A pixel value of 0 is transparent and shows the backdrop, palette entry 0
# (https://www.nesdev.org/wiki/PPU_palettes). A pixel is the 4-bit palette entry: palette in bits 3-2, pattern in 1-0.
RSpec.describe Ruby::Nes::Ppu::BackgroundVisibility do
  describe '#palette_entry' do
    context 'when the background is disabled' do
      subject(:visibility) { described_class.new(background_enabled: false, left_columns_shown: true) }

      it 'is the backdrop entry' do
        expect(visibility.palette_entry(100, 0b10_11)).to eq(0)
      end
    end

    context 'when the background is enabled' do
      context 'but the pixel is transparent' do
        subject(:visibility) { described_class.new(background_enabled: true, left_columns_shown: true) }

        it 'is the backdrop entry' do
          expect(visibility.palette_entry(100, 0b10_00)).to eq(0)
        end
      end

      context 'and the pixel is opaque' do
        context 'and it is in the leftmost 8 columns' do
          context 'but they are hidden' do
            subject(:visibility) { described_class.new(background_enabled: true, left_columns_shown: false) }

            it 'is the backdrop entry' do
              expect(visibility.palette_entry(7, 0b10_01)).to eq(0)
            end
          end

          context 'and they are shown' do
            subject(:visibility) { described_class.new(background_enabled: true, left_columns_shown: true) }

            it "is the pixel's entry" do
              expect(visibility.palette_entry(7, 0b10_01)).to eq(0b10_01)
            end
          end
        end

        context 'and it is right of the leftmost 8 columns' do
          context 'and they are hidden' do
            subject(:visibility) { described_class.new(background_enabled: true, left_columns_shown: false) }

            it "is the pixel's entry" do
              expect(visibility.palette_entry(8, 0b10_01)).to eq(0b10_01)
            end
          end

          context 'and they are shown' do
            subject(:visibility) { described_class.new(background_enabled: true, left_columns_shown: true) }

            it "is the pixel's entry" do
              expect(visibility.palette_entry(8, 0b10_01)).to eq(0b10_01)
            end
          end
        end
      end
    end
  end
end
