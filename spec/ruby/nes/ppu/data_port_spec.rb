# frozen_string_literal: true

# PPUDATA (https://www.nesdev.org/wiki/PPU_registers): reads return "the contents of an internal read buffer", which
# starts at $00 and is cleared by the PPU's reset signal (https://www.nesdev.org/wiki/PPU_power_up_state); palette data
# "is returned immediately instead of going to the internal read buffer", with "PPU open bus in the top 2 bits",
# greyscale "bitwise ANDing the color with $30", while "a normal read from PPU memory at the specified address,
# "underneath" the palette data" fills the buffer (plan 11, decision 8: the nametable byte $1000 below). "After access,
# the video memory address will increment by an amount determined by bit 2 of $2000"; "The highest bit [of v] is unused
# for access through $2007" (https://www.nesdev.org/wiki/PPU_scrolling).
RSpec.describe Ruby::Nes::Ppu::DataPort do
  describe '#read' do
    context 'when the address is below the palette' do
      subject(:data_port) { described_class.new(bus:, scroll_registers:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }

      context 'and nothing was read before' do
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

        before { allow(bus).to receive(:read).with(0x2005).and_return(0x5A) }

        it 'returns 0' do
          expect(data_port.read(0x00)).to eq(0x00)
        end
      end

      context 'and a byte was read before' do
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

        before do
          allow(bus).to receive(:read).with(0x2005).and_return(0x5A)
          allow(bus).to receive(:read).with(0x2006).and_return(0xA5)
          data_port.read(0x00)
        end

        it 'returns the byte the previous read buffered' do
          expect(data_port.read(0x00)).to eq(0x5A)
        end
      end

      context 'and it is $3EFF' do
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3EFF) }

        before { allow(bus).to receive(:read).with(0x3EFF).and_return(0x5A) }

        it 'returns the buffer, not the byte at $3EFF' do
          expect(data_port.read(0x00)).to eq(0x00)
        end
      end
    end

    context 'when the address is in the palette' do
      subject(:data_port) { described_class.new(bus:, scroll_registers:, greyscale:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }

      context 'and it is $3F00' do
        let(:greyscale) { false }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3F00) }

        before do
          allow(bus).to receive(:read).with(0x3F00).and_return(0x2C)
          allow(bus).to receive(:read).with(0x2F00).and_return(0x77)
        end

        it 'returns the colour at once' do
          expect(data_port.read(0x00)).to eq(0x2C)
        end
      end

      context 'and greyscale is off' do
        let(:greyscale) { false }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3F1F) }

        before do
          allow(bus).to receive(:read).with(0x3F1F).and_return(0x2C)
          allow(bus).to receive(:read).with(0x2F1F).and_return(0x77)
        end

        it 'returns the colour with bits 7-6 of the open bus' do
          expect(data_port.read(0xBF)).to eq(0xAC)
        end
      end

      context 'and greyscale is on' do
        let(:greyscale) { true }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3F1F) }

        before do
          allow(bus).to receive(:read).with(0x3F1F).and_return(0x2C)
          allow(bus).to receive(:read).with(0x2F1F).and_return(0x77)
        end

        it "returns the colour's bits 5-4 with bits 7-6 of the open bus" do
          expect(data_port.read(0xBF)).to eq(0xA0)
        end
      end

      context 'and the next read is below the palette' do
        let(:greyscale) { false }
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3FFF) }

        before do
          allow(bus).to receive(:read).with(0x3FFF).and_return(0x2C)
          allow(bus).to receive(:read).with(0x2FFF).and_return(0x77)
          allow(bus).to receive(:read).with(0x0000).and_return(0x11)
          data_port.read(0x00)
        end

        it 'returns the nametable byte underneath the palette' do
          expect(data_port.read(0x00)).to eq(0x77)
        end
      end
    end

    context 'when v has its fifteenth bit set' do
      subject(:data_port) { described_class.new(bus:, scroll_registers:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x6005) }

      before do
        allow(bus).to receive(:read).with(0x2005).and_return(0x5A)
        allow(bus).to receive(:read).with(0x2006).and_return(0xA5)
        data_port.read(0x00)
      end

      it 'reads the address in its low 14 bits' do
        expect(data_port.read(0x00)).to eq(0x5A)
      end
    end

    context 'when the increment is 1' do
      subject(:data_port) { described_class.new(bus:, scroll_registers:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus, read: 0x00) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

      it 'advances v by 1' do
        expect { data_port.read(0x00) }.to change(scroll_registers, :vram_address).from(0x2005).to(0x2006)
      end
    end

    context 'when the increment is 32' do
      subject(:data_port) { described_class.new(bus:, scroll_registers:, increment: 32) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus, read: 0x00) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

      it 'advances v by 32' do
        expect { data_port.read(0x00) }.to change(scroll_registers, :vram_address).from(0x2005).to(0x2025)
      end
    end
  end

  describe '#write' do
    context 'when v holds a 14-bit address' do
      subject(:data_port) { described_class.new(bus:, scroll_registers:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus, write: nil) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

      before { data_port.write(0x5A) }

      it 'stores the byte at v' do
        expect(bus).to have_received(:write).with(0x2005, 0x5A)
      end
    end

    context 'when v has its fifteenth bit set' do
      subject(:data_port) { described_class.new(bus:, scroll_registers:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus, write: nil) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x6005) }

      before { data_port.write(0x5A) }

      it 'stores the byte at the address in its low 14 bits' do
        expect(bus).to have_received(:write).with(0x2005, 0x5A)
      end
    end

    context 'when the increment is 1' do
      subject(:data_port) { described_class.new(bus:, scroll_registers:) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus, write: nil) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

      it 'advances v by 1' do
        expect { data_port.write(0x5A) }.to change(scroll_registers, :vram_address).from(0x2005).to(0x2006)
      end
    end

    context 'when the increment is 32' do
      subject(:data_port) { described_class.new(bus:, scroll_registers:, increment: 32) }

      let(:bus) { instance_double(Ruby::Nes::PpuBus, write: nil) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

      it 'advances v by 32' do
        expect { data_port.write(0x5A) }.to change(scroll_registers, :vram_address).from(0x2005).to(0x2025)
      end
    end
  end

  describe '#clear_read_buffer' do
    subject(:data_port) { described_class.new(bus:, scroll_registers:) }

    let(:bus) { instance_double(Ruby::Nes::PpuBus) }
    let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

    before do
      allow(bus).to receive(:read).with(0x2005).and_return(0x5A)
      allow(bus).to receive(:read).with(0x2006).and_return(0xA5)
      data_port.read(0x00)
      data_port.clear_read_buffer
    end

    it 'makes the next read below the palette return 0' do
      expect(data_port.read(0x00)).to eq(0x00)
    end
  end
end
