# frozen_string_literal: true

# Which pixels of a layer show (https://www.nesdev.org/wiki/PPU_registers, PPUMASK): bit 3 "Enable background rendering"
# and bit 4 "Enable sprite rendering", "If one component is enabled and the other is not, the disabled component is
# simply treated as transparent"; bits 1 and 2 "Show background/sprites in leftmost 8 pixels of screen, 0: Hide",
# hiding them "making them transparent and thus drawing the backdrop color there". A pixel value of 0 is transparent,
# palette entry 0 (https://www.nesdev.org/wiki/PPU_palettes). A pixel is its palette entry: pattern value in bits 1-0.
RSpec.describe Ruby::Nes::Ppu::LayerVisibility do
  describe '#palette_entry' do
    context 'when the layer is disabled' do
      subject(:visibility) { described_class.new(enabled: false, left_columns_shown: true) }

      it 'is the backdrop entry' do
        expect(visibility.palette_entry(100, 0b10_11)).to eq(0)
      end
    end

    context 'when the layer is enabled' do
      context 'but the pixel is transparent' do
        subject(:visibility) { described_class.new(enabled: true, left_columns_shown: true) }

        it 'is the backdrop entry' do
          expect(visibility.palette_entry(100, 0b10_00)).to eq(0)
        end
      end

      context 'and the pixel is opaque' do
        context 'and it is in the leftmost 8 columns' do
          context 'but they are hidden' do
            subject(:visibility) { described_class.new(enabled: true, left_columns_shown: false) }

            it 'is the backdrop entry' do
              expect(visibility.palette_entry(7, 0b10_01)).to eq(0)
            end
          end

          context 'and they are shown' do
            subject(:visibility) { described_class.new(enabled: true, left_columns_shown: true) }

            it "is the pixel's entry" do
              expect(visibility.palette_entry(7, 0b10_01)).to eq(0b10_01)
            end
          end
        end

        context 'and it is right of the leftmost 8 columns' do
          context 'and they are hidden' do
            subject(:visibility) { described_class.new(enabled: true, left_columns_shown: false) }

            it "is the pixel's entry" do
              expect(visibility.palette_entry(8, 0b10_01)).to eq(0b10_01)
            end
          end

          context 'and they are shown' do
            subject(:visibility) { described_class.new(enabled: true, left_columns_shown: true) }

            it "is the pixel's entry" do
              expect(visibility.palette_entry(8, 0b10_01)).to eq(0b10_01)
            end
          end
        end
      end
    end
  end
end
