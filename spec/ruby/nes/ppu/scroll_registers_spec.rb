# frozen_string_literal: true

# The "Register controls" table of https://www.nesdev.org/wiki/PPU_scrolling: v and t are 15 bits, x is 3 bits, w is
# the write toggle shared by $2005 and $2006; outside rendering $2007 "will add either 1 or 32 to v".
RSpec.describe Ruby::Nes::Ppu::ScrollRegisters do
  describe '#write_control' do
    subject(:scroll_registers) { described_class.new(temporary_address: 0x5555) }

    before { scroll_registers.write_control(0xFE) }

    it 'places bits 1-0 at t bits 11-10 and keeps the rest of t' do
      expect(scroll_registers.temporary_address).to eq(0x5955)
    end
  end

  describe '#write_scroll' do
    context 'when it is the first write' do
      subject(:scroll_registers) { described_class.new(temporary_address: 0x5555, vram_address: 0x1234) }

      before { scroll_registers.write_scroll(0x53) }

      it 'places bits 7-3 at t bits 4-0, bits 2-0 in x, and sets w', :aggregate_failures do
        expect(scroll_registers)
          .to have_attributes(temporary_address: 0x554A, fine_x: 0b011, second_write?: true, vram_address: 0x1234)
      end
    end

    context 'when it is the second write' do
      subject(:scroll_registers) do
        described_class.new(temporary_address: 0x5555, fine_x: 0b101, second_write: true, vram_address: 0x1234)
      end

      before { scroll_registers.write_scroll(0xAE) }

      it 'places bits 2-0 at t bits 14-12 and bits 7-3 at t bits 9-5, and clears w', :aggregate_failures do
        expect(scroll_registers)
          .to have_attributes(temporary_address: 0x66B5, fine_x: 0b101, second_write?: false, vram_address: 0x1234)
      end
    end
  end

  describe '#write_address' do
    context 'when it is the first write' do
      subject(:scroll_registers) { described_class.new(temporary_address: 0x5555, vram_address: 0x1234) }

      before { scroll_registers.write_address(0xEA) }

      it 'places bits 5-0 at t bits 13-8, clears t bit 14, and sets w', :aggregate_failures do
        expect(scroll_registers)
          .to have_attributes(temporary_address: 0x2A55, second_write?: true, vram_address: 0x1234)
      end
    end

    context 'when it is the second write' do
      subject(:scroll_registers) do
        described_class.new(temporary_address: 0x2A55, second_write: true, vram_address: 0x1234)
      end

      before { scroll_registers.write_address(0x9C) }

      it 'places the byte at t bits 7-0, copies t to v, and clears w', :aggregate_failures do
        expect(scroll_registers)
          .to have_attributes(temporary_address: 0x2A9C, vram_address: 0x2A9C, second_write?: false)
      end
    end
  end

  describe '#reset_write_toggle' do
    subject(:scroll_registers) { described_class.new(second_write: true) }

    before { scroll_registers.reset_write_toggle }

    it 'clears w' do
      expect(scroll_registers).not_to be_second_write
    end
  end

  describe '#increment_vram_address' do
    context 'when v stays below $4000' do
      subject(:scroll_registers) { described_class.new(vram_address: 0x2000) }

      before { scroll_registers.increment_vram_address(1) }

      it 'adds the increment to v' do
        expect(scroll_registers.vram_address).to eq(0x2001)
      end
    end

    context 'when v goes past $3FFF' do
      subject(:scroll_registers) { described_class.new(vram_address: 0x3FFF) }

      before { scroll_registers.increment_vram_address(32) }

      it 'keeps the fifteenth bit' do
        expect(scroll_registers.vram_address).to eq(0x401F)
      end
    end

    context 'when v goes past $7FFF' do
      subject(:scroll_registers) { described_class.new(vram_address: 0x7FF0) }

      before { scroll_registers.increment_vram_address(32) }

      it 'wraps to 15 bits' do
        expect(scroll_registers.vram_address).to eq(0x0010)
      end
    end
  end
end
