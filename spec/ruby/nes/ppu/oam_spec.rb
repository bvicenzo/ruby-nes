# frozen_string_literal: true

# OAM facts: 64 sprites of 4 bytes; byte 2's bits 2-4 are "Unimplemented (read 0)", emulated "by ANDing byte 2 with
# $E3 either when writing to or when reading from OAM" (https://www.nesdev.org/wiki/PPU_OAM). OAMDATA: "Writes will
# increment OAMADDR after the write; reads do not." (https://www.nesdev.org/wiki/PPU_registers).
RSpec.describe Ruby::Nes::Ppu::Oam do
  describe '#write' do
    context "when the address holds a sprite's byte 0, 1 or 3" do
      subject(:oam) { described_class.new(address: 0x43) }

      it 'stores the whole byte' do
        oam.write(0xFF)
        oam.address = 0x43
        expect(oam.read).to eq(0xFF)
      end
    end

    context "when the address holds a sprite's byte 2" do
      subject(:oam) { described_class.new(address: 0x42) }

      it 'stores the byte with its unimplemented bits 4-2 cleared' do
        oam.write(0xFF)
        oam.address = 0x42
        expect(oam.read).to eq(0xE3)
      end
    end

    context 'when the address is below $FF' do
      subject(:oam) { described_class.new(address: 0xFE) }

      it 'moves the address to the next byte' do
        expect { oam.write(0x12) }.to change(oam, :address).from(0xFE).to(0xFF)
      end
    end

    context 'when the address is $FF' do
      subject(:oam) { described_class.new(address: 0xFF) }

      it 'wraps the address to $00' do
        expect { oam.write(0x12) }.to change(oam, :address).from(0xFF).to(0x00)
      end
    end
  end

  describe '#read' do
    context 'when nothing was written' do
      subject(:oam) { described_class.new(address: 0x10) }

      it 'returns 0' do
        expect(oam.read).to eq(0x00)
      end
    end

    context 'when a byte was written at the address' do
      subject(:oam) { described_class.new(address: 0x10) }

      before { oam.write(0x7C) }

      it 'returns the byte and leaves the address unchanged', :aggregate_failures do
        oam.address = 0x10
        expect(oam.read).to eq(0x7C)
        expect(oam.address).to eq(0x10)
      end
    end
  end

  describe '#byte' do
    context 'when nothing was written at the address' do
      subject(:oam) { described_class.new(address: 0x10) }

      it 'returns 0' do
        expect(oam.byte(0x25)).to eq(0x00)
      end
    end

    context 'when a byte was written at the address' do
      subject(:oam) { described_class.new(address: 0x25) }

      before { oam.write(0x7C) }

      it 'returns the byte' do
        expect(oam.byte(0x25)).to eq(0x7C)
      end

      it 'leaves OAMADDR where it is' do
        expect { oam.byte(0x25) }.not_to change(oam, :address).from(0x26)
      end
    end
  end
end
