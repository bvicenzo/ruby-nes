# frozen_string_literal: true

# Sprite 0 hit (https://www.nesdev.org/wiki/PPU_OAM): "when an opaque pixel of sprite 0 overlaps an opaque pixel of the
# background", the PPU "sets bit 6 of PPUSTATUS"; it does not happen "At x=255, for an obscure reason related to the
# pixel pipeline". The caller checks only pixels where both are opaque and visible (PriorityMultiplexer). A sprite line
# entry carries bit 6 for a pixel of sprite 0.
RSpec.describe Ruby::Nes::Ppu::SpriteZeroHit do
  describe '#check' do
    subject(:sprite_zero_hit) { described_class.new(status:) }

    let(:status) { instance_double(Ruby::Nes::Ppu::SpriteStatus, sprite_zero_hit: nil) }

    context 'when the sprite pixel is not of sprite 0' do
      before { sprite_zero_hit.check(100, 0x11) }

      it 'leaves the status alone' do
        expect(status).not_to have_received(:sprite_zero_hit)
      end
    end

    context 'when the sprite pixel is of sprite 0' do
      context 'but the column is 255' do
        before { sprite_zero_hit.check(255, 0x51) }

        it 'leaves the status alone' do
          expect(status).not_to have_received(:sprite_zero_hit)
        end
      end

      context 'and the column is before 255' do
        before { sprite_zero_hit.check(254, 0x51) }

        it 'tells the status sprite 0 hit' do
          expect(status).to have_received(:sprite_zero_hit)
        end
      end
    end
  end
end
