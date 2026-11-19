# frozen_string_literal: true

# PPUSTATUS (https://www.nesdev.org/wiki/PPU_registers): bit 5 is the "Sprite overflow flag", bit 6 the "Sprite 0 hit
# flag"; both stay set until they are "automatically cleared on dot 1 of the prerender scanline".
RSpec.describe Ruby::Nes::Ppu::SpriteStatus do
  describe '#bits' do
    subject(:status) { described_class.new }

    context 'when no flag is set' do
      it 'is 0' do
        expect(status.bits).to eq(0x00)
      end
    end

    context 'when the sprites overflowed' do
      before { status.overflow_found }

      it 'has bit 5 set' do
        expect(status.bits).to eq(0x20)
      end
    end

    context 'when sprite 0 hit' do
      before { status.sprite_zero_hit }

      it 'has bit 6 set' do
        expect(status.bits).to eq(0x40)
      end
    end

    context 'when both happened' do
      before do
        status.overflow_found
        status.sprite_zero_hit
      end

      it 'has bits 6 and 5 set' do
        expect(status.bits).to eq(0x60)
      end
    end
  end

  describe '#clear' do
    subject(:status) { described_class.new }

    before do
      status.overflow_found
      status.sprite_zero_hit
    end

    it 'clears both flags' do
      expect { status.clear }.to change(status, :bits).from(0x60).to(0x00)
    end
  end
end
