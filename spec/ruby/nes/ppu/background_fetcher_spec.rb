# frozen_string_literal: true

# The background's memory fetches (https://www.nesdev.org/wiki/PPU_rendering): nametable byte, attribute table byte,
# pattern table tile low and tile high, "8 bytes above pattern table tile low address". Their addresses come from v
# ("tile address = 0x2000 | (v & 0x0FFF)", "attribute address = 0x23C0 | (v & 0x0C00) | ((v >> 4) & 0x38) | ((v >> 2)
# & 0x07)", https://www.nesdev.org/wiki/PPU_scrolling) and, for the patterns, from PPUCTRL bit 4, "Background pattern
# table address (0: $0000; 1: $1000)", with the layout "0HNNNN NNNNPyyy"
# (https://www.nesdev.org/wiki/PPU_pattern_tables).
# An attribute byte is "(bottomright << 6) | (bottomleft << 4) | (topright << 2) | (topleft << 0)"
# (https://www.nesdev.org/wiki/PPU_attribute_tables); coarse X bit 1 and coarse Y bit 1 pick the quadrant (plan 13).
# The comments spell v as fine Y, nametable select, coarse Y and coarse X.
RSpec.describe Ruby::Nes::Ppu::BackgroundFetcher do
  describe '#fetch_nametable_byte' do
    subject(:fetcher) { described_class.new(bus:, scroll_registers:) }

    # 5, 2, 12, 9.
    let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x5989) }
    let(:bus) { instance_double(Ruby::Nes::PpuBus) }

    before do
      allow(bus).to receive(:read).with(0x2989).and_return(0x47)
      fetcher.fetch_nametable_byte
    end

    it 'reads the tile number at $2000 plus the low 12 bits of v' do
      expect(fetcher.tile).to eq(0x47)
    end
  end

  describe '#fetch_attribute' do
    subject(:fetcher) { described_class.new(bus:, scroll_registers:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }

    context 'when v is in the top-left quadrant' do
      # 5, 2, 12, 9: attribute row 3, column 2, coarse Y bit 1 and coarse X bit 1 clear.
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x5989) }

      before do
        allow(bus).to receive(:read).with(0x2BDA).and_return(0b11_10_01_00)
        fetcher.fetch_attribute
      end

      it 'keeps bits 1-0 of the attribute byte' do
        expect(fetcher.palette).to eq(0b00)
      end
    end

    context 'when v is in the top-right quadrant' do
      # 5, 2, 12, 11.
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x598B) }

      before do
        allow(bus).to receive(:read).with(0x2BDA).and_return(0b11_10_01_00)
        fetcher.fetch_attribute
      end

      it 'keeps bits 3-2 of the attribute byte' do
        expect(fetcher.palette).to eq(0b01)
      end
    end

    context 'when v is in the bottom-left quadrant' do
      # 5, 2, 14, 9.
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x59C9) }

      before do
        allow(bus).to receive(:read).with(0x2BDA).and_return(0b11_10_01_00)
        fetcher.fetch_attribute
      end

      it 'keeps bits 5-4 of the attribute byte' do
        expect(fetcher.palette).to eq(0b10)
      end
    end

    context 'when v is in the bottom-right quadrant' do
      # 5, 2, 14, 11.
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x59CB) }

      before do
        allow(bus).to receive(:read).with(0x2BDA).and_return(0b11_10_01_00)
        fetcher.fetch_attribute
      end

      it 'keeps bits 7-6 of the attribute byte' do
        expect(fetcher.palette).to eq(0b11)
      end
    end
  end

  describe '#fetch_pattern_low' do
    # 5, 2, 12, 9.
    let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x5989) }
    let(:bus) { instance_double(Ruby::Nes::PpuBus) }

    context 'when the background uses pattern table 0' do
      subject(:fetcher) { described_class.new(bus:, scroll_registers:, pattern_table: 0x0000) }

      before do
        allow(bus).to receive(:read).with(0x2989).and_return(0x47)
        allow(bus).to receive(:read).with(0x0475).and_return(0xC3)
        fetcher.fetch_nametable_byte
        fetcher.fetch_pattern_low
      end

      it "reads the row of fine Y of the tile's plane 0 in the table at $0000" do
        expect(fetcher.pattern_low).to eq(0xC3)
      end
    end

    context 'when the background uses pattern table 1' do
      subject(:fetcher) { described_class.new(bus:, scroll_registers:, pattern_table: 0x1000) }

      before do
        allow(bus).to receive(:read).with(0x2989).and_return(0x47)
        allow(bus).to receive(:read).with(0x1475).and_return(0xC3)
        fetcher.fetch_nametable_byte
        fetcher.fetch_pattern_low
      end

      it "reads the row of fine Y of the tile's plane 0 in the table at $1000" do
        expect(fetcher.pattern_low).to eq(0xC3)
      end
    end
  end

  describe '#fetch_pattern_high' do
    subject(:fetcher) { described_class.new(bus:, scroll_registers:, pattern_table: 0x1000) }

    # 5, 2, 12, 9.
    let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x5989) }
    let(:bus) { instance_double(Ruby::Nes::PpuBus) }

    before do
      allow(bus).to receive(:read).with(0x2989).and_return(0x47)
      allow(bus).to receive(:read).with(0x147D).and_return(0x3C)
      fetcher.fetch_nametable_byte
      fetcher.fetch_pattern_high
    end

    it 'reads the same row of plane 1, 8 bytes above' do
      expect(fetcher.pattern_high).to eq(0x3C)
    end
  end
end
