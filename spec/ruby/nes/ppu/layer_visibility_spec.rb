# frozen_string_literal: true

# Which columns of a layer show (https://www.nesdev.org/wiki/PPU_registers, PPUMASK): bit 3 "Enable background
# rendering" and bit 4 "Enable sprite rendering", "If one component is enabled and the other is not, the disabled
# component is simply treated as transparent"; bits 1 and 2 "Show background/sprites in leftmost 8 pixels of screen, 0:
# Hide", hiding them "making them transparent and thus drawing the backdrop color there". The renderer shows a layer's
# pixel from the first visible column on (plan 25, decision 7); 256 is past the last column, so a disabled layer shows
# none.
RSpec.describe Ruby::Nes::Ppu::LayerVisibility do
  describe '#first_visible_column' do
    context 'when the layer is disabled' do
      context 'and the leftmost 8 columns are shown' do
        subject(:visibility) { described_class.new(enabled: false, left_columns_shown: true) }

        it 'is 256, no column' do
          expect(visibility.first_visible_column).to eq(256)
        end
      end

      context 'and the leftmost 8 columns are hidden' do
        subject(:visibility) { described_class.new(enabled: false, left_columns_shown: false) }

        it 'is 256, no column' do
          expect(visibility.first_visible_column).to eq(256)
        end
      end
    end

    context 'when the layer is enabled' do
      context 'and the leftmost 8 columns are hidden' do
        subject(:visibility) { described_class.new(enabled: true, left_columns_shown: false) }

        it 'is 8' do
          expect(visibility.first_visible_column).to eq(8)
        end
      end

      context 'and the leftmost 8 columns are shown' do
        subject(:visibility) { described_class.new(enabled: true, left_columns_shown: true) }

        it 'is 0' do
          expect(visibility.first_visible_column).to eq(0)
        end
      end
    end
  end

  describe '#enabled=' do
    subject(:visibility) { described_class.new(enabled: false, left_columns_shown: true) }

    it 'moves the first visible column' do
      expect { visibility.enabled = true }.to change(visibility, :first_visible_column).from(256).to(0)
    end
  end

  describe '#left_columns_shown=' do
    subject(:visibility) { described_class.new(enabled: true, left_columns_shown: false) }

    it 'moves the first visible column' do
      expect { visibility.left_columns_shown = true }.to change(visibility, :first_visible_column).from(8).to(0)
    end
  end
end
