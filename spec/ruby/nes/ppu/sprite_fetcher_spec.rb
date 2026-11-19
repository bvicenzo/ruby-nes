# frozen_string_literal: true

# The sprite fetches of dots 257-320 (https://www.nesdev.org/wiki/PPU_rendering): for each of the 8 slots of secondary
# OAM, "Pattern table tile low" and "Pattern table tile high (8 bytes above pattern table tile low address)"; with
# fewer than 8 sprites, "dummy fetches to tile $FF occur for the left-over sprites" and "the sprites are loaded with a
# transparent set of values instead". The row is the scanline minus Y: the sprites are fetched on the scanline before
# the one they show on, and Y is "delayed by one scanline" (https://www.nesdev.org/wiki/PPU_OAM); a derivation. Sprite
# 0 hit "relies on the fact that sprite 0, when it is within y range for the next scanline, always gets assigned the
# first sprite output unit" (https://www.nesdev.org/wiki/PPU_OAM): SecondaryOam knows which slot holds it.
RSpec.describe Ruby::Nes::Ppu::SpriteFetcher do
  describe '#fetch_pattern_low' do
    subject(:fetcher) { described_class.new(bus:, secondary_oam:, line:, pattern_address:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:line) { instance_double(Ruby::Nes::Ppu::SpriteLine) }
    let(:secondary_oam) { instance_double(Ruby::Nes::Ppu::SecondaryOam) }
    let(:pattern_address) { instance_double(Ruby::Nes::Ppu::SpritePatternAddress::EightByEight) }

    before do
      allow(secondary_oam).to receive(:y_position).with(2).and_return(90)
      allow(secondary_oam).to receive(:tile).with(2).and_return(0x2A)
      allow(secondary_oam).to receive(:attributes).with(2).and_return(0x81)
      allow(pattern_address).to receive(:address).with(0x2A, 10, 0x81).and_return(0x12A5)
      allow(bus).to receive(:read).with(0x12A5).and_return(0x3C)
    end

    it "reads the address the pattern gives for the slot's tile, its row on the scanline and its attributes" do
      expect(fetcher.fetch_pattern_low(2, 100)).to eq(0x3C)
    end
  end

  describe '#fetch_pattern_high' do
    subject(:fetcher) { described_class.new(bus:, secondary_oam:, line:, pattern_address:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:line) { instance_double(Ruby::Nes::Ppu::SpriteLine) }
    let(:secondary_oam) do
      instance_double(Ruby::Nes::Ppu::SecondaryOam, y_position: 90, tile: 0x2A, attributes: 0x81)
    end
    let(:pattern_address) { instance_double(Ruby::Nes::Ppu::SpritePatternAddress::EightByEight, address: 0x12A5) }

    before do
      allow(bus).to receive(:read).with(0x12A5).and_return(0x3C)
      allow(bus).to receive(:read).with(0x12AD).and_return(0xC3)
      fetcher.fetch_pattern_low(2, 100)
    end

    it "reads 8 bytes above the low plane's address" do
      expect(fetcher.fetch_pattern_high).to eq(0xC3)
    end
  end

  describe '#load_sprite' do
    subject(:fetcher) { described_class.new(bus:, secondary_oam:, line:, pattern_address:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:line) { instance_double(Ruby::Nes::Ppu::SpriteLine, place: nil) }
    let(:pattern_address) { instance_double(Ruby::Nes::Ppu::SpritePatternAddress::EightByEight, address: 0x12A5) }

    before do
      allow(bus).to receive(:read).with(0x12A5).and_return(0x3C)
      allow(bus).to receive(:read).with(0x12AD).and_return(0xC3)
    end

    context 'when the slot is empty' do
      let(:secondary_oam) do
        instance_double(Ruby::Nes::Ppu::SecondaryOam, count: 2, y_position: 0xFF, tile: 0xFF, attributes: 0xFF)
      end

      before do
        fetcher.fetch_pattern_low(2, 100)
        fetcher.fetch_pattern_high
        fetcher.load_sprite(2)
      end

      it 'places nothing' do
        expect(line).not_to have_received(:place)
      end
    end

    context 'when the slot holds a sprite' do
      let(:secondary_oam) do
        instance_double(
          Ruby::Nes::Ppu::SecondaryOam,
          count: 3,
          y_position: 90,
          tile: 0x2A,
          attributes: 0x41,
          x_position: 0x80
        )
      end

      before do
        allow(secondary_oam).to receive(:sprite_zero?).with(1).and_return(true)
        fetcher.fetch_pattern_low(1, 100)
        fetcher.fetch_pattern_high
        fetcher.load_sprite(1)
      end

      it "places the fetched row at its X with its attributes and the slot's sprite 0 mark" do
        expect(line).to have_received(:place).with(0x80, 0x3C, 0xC3, 0x41, true)
      end
    end
  end
end
