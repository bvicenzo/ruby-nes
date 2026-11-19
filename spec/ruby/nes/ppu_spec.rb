# frozen_string_literal: true

# PPU registers (https://www.nesdev.org/wiki/PPU_registers) and the PPU's I/O latch
# (https://www.nesdev.org/wiki/Open_bus_behavior#PPU_open_bus): "Writes to any PPU port, including the nominally
# read-only status port at $2002, load a value onto the PPU's I/O bus"; "Reading a nominally "write-only" register
# returns the latch's current value, as do the unused bits of PPUSTATUS"; "Reading the PPU's status port loads a value
# onto bits 7-5 of the bus, leaving the rest unchanged"; "Reading a value from $2004 or $2007 loads a byte [...] onto
# this bus". PPUSTATUS: "Reading this register has the side effect of clearing the PPU's internal w register". The
# VBlank, sprite 0 hit and overflow flags are plans 12 and 14 (plan 11, decision 4): bits 7-5 read 0 here.
RSpec.describe Ruby::Nes::Ppu do
  describe '#cpu_write' do
    subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

    context 'when the address is $2000' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus, read: 0x00) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

      context 'and bits 1-0 select nametable 3' do
        before { ppu.cpu_write(0x2000, 0x03) }

        it 'places the select at t bits 11-10 and loads the byte into the latch', :aggregate_failures do
          expect(scroll_registers.temporary_address).to eq(0x0C00)
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x03)
        end
      end

      context 'and bit 2 is clear' do
        before { ppu.cpu_write(0x2000, 0x00) }

        it 'makes PPUDATA advance v by 1' do
          expect { ppu.cpu_read(0x2007, 0x00) }.to change(scroll_registers, :vram_address).to(0x2006)
        end
      end

      context 'and bit 2 is set' do
        before { ppu.cpu_write(0x2000, 0x04) }

        it 'makes PPUDATA advance v by 32' do
          expect { ppu.cpu_read(0x2007, 0x00) }.to change(scroll_registers, :vram_address).to(0x2025)
        end
      end
    end

    context 'when the address is $2001' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3F00) }

      context 'and bits 7-1 hold the other rendering settings' do
        before { ppu.cpu_write(0x2001, 0x1E) }

        it 'loads the byte into the latch' do
          expect(ppu.cpu_read(0x2001, 0x00)).to eq(0x1E)
        end
      end

      context 'and bit 0 is clear' do
        before do
          allow(bus).to receive(:read).with(0x3F00).and_return(0x2C)
          allow(bus).to receive(:read).with(0x2F00).and_return(0x00)
          ppu.cpu_write(0x2001, 0x18)
        end

        it 'makes palette reads keep the colour' do
          expect(ppu.cpu_read(0x2007, 0x00)).to eq(0x2C)
        end
      end

      context 'and bit 0 is set' do
        before do
          allow(bus).to receive(:read).with(0x3F00).and_return(0x2C)
          allow(bus).to receive(:read).with(0x2F00).and_return(0x00)
          ppu.cpu_write(0x2001, 0x01)
        end

        it "makes palette reads keep the colour's bits 5-4" do
          expect(ppu.cpu_read(0x2007, 0x00)).to eq(0x20)
        end
      end
    end

    context 'when the address is $2002' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(temporary_address: 0x1234, second_write: true) }

      before { ppu.cpu_write(0x2002, 0x5A) }

      it 'only loads the latch', :aggregate_failures do
        expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x5A)
        expect(scroll_registers).to have_attributes(temporary_address: 0x1234, second_write?: true)
      end
    end

    context 'when the address is $2003' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }

      before { ppu.cpu_write(0x2003, 0x40) }

      it 'sets OAMADDR and loads the latch', :aggregate_failures do
        expect(oam.address).to eq(0x40)
        expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x40)
      end
    end

    context 'when the address is $2004' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }
      let(:oam) { Ruby::Nes::Ppu::Oam.new(address: 0x40) }

      before { ppu.cpu_write(0x2004, 0x7C) }

      it 'writes the byte to OAM and loads the latch', :aggregate_failures do
        expect(oam.address).to eq(0x41)
        oam.address = 0x40
        expect(oam.read).to eq(0x7C)
        expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x7C)
      end
    end

    context 'when the address is $2005' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }

      before { ppu.cpu_write(0x2005, 0x53) }

      it 'writes the scroll and loads the latch', :aggregate_failures do
        expect(scroll_registers).to have_attributes(temporary_address: 0x000A, fine_x: 0b011, second_write?: true)
        expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x53)
      end
    end

    context 'when the address is $2006' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }

      before { ppu.cpu_write(0x2006, 0x21) }

      it 'writes the address and loads the latch', :aggregate_failures do
        expect(scroll_registers).to have_attributes(temporary_address: 0x2100, second_write?: true)
        expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x21)
      end
    end

    context 'when the address is $2007' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus, write: nil) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

      before { ppu.cpu_write(0x2007, 0x99) }

      it 'writes the byte at v and loads the latch', :aggregate_failures do
        expect(bus).to have_received(:write).with(0x2005, 0x99)
        expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x99)
      end
    end
  end

  describe '#cpu_read' do
    subject(:ppu) { described_class.new(bus:, scroll_registers:, oam:) }

    context 'when the address is a write-only register' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }

      before { ppu.cpu_write(0x2002, 0x5A) }

      context 'and it is $2000' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2000, 0xFF)).to eq(0x5A)
        end
      end

      context 'and it is $2001' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2001, 0xFF)).to eq(0x5A)
        end
      end

      context 'and it is $2003' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2003, 0xFF)).to eq(0x5A)
        end
      end

      context 'and it is $2005' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2005, 0xFF)).to eq(0x5A)
        end
      end

      context 'and it is $2006' do
        it 'returns the latch, whatever is on the CPU data bus' do
          expect(ppu.cpu_read(0x2006, 0xFF)).to eq(0x5A)
        end
      end
    end

    context 'when the address is $2002' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(second_write: true) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }

      before { ppu.cpu_write(0x2002, 0xFF) }

      it 'returns bits 7-5 clear and bits 4-0 of the latch' do
        expect(ppu.cpu_read(0x2002, 0x00)).to eq(0x1F)
      end

      it 'clears w' do
        expect { ppu.cpu_read(0x2002, 0x00) }.to change(scroll_registers, :second_write?).from(true).to(false)
      end

      it 'loads its bits 7-5 into the latch and keeps bits 4-0' do
        ppu.cpu_read(0x2002, 0x00)
        expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x1F)
      end
    end

    context 'when the address is $2004' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new }
      let(:oam) { Ruby::Nes::Ppu::Oam.new(address: 0x40) }

      before do
        oam.write(0x7C)
        ppu.cpu_write(0x2003, 0x40)
      end

      it 'returns the OAM byte at OAMADDR and loads it into the latch', :aggregate_failures do
        expect(ppu.cpu_read(0x2004, 0x00)).to eq(0x7C)
        expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x7C)
      end
    end

    context 'when the address is $2007' do
      let(:bus) { instance_double(Ruby::Nes::PpuBus) }
      let(:oam) { Ruby::Nes::Ppu::Oam.new }

      context 'and v is below the palette' do
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x2005) }

        before do
          allow(bus).to receive(:read).with(0x2005).and_return(0x5A)
          allow(bus).to receive(:read).with(0x2006).and_return(0xA5)
          ppu.cpu_read(0x2007, 0x00)
        end

        it 'returns the buffered byte and loads it into the latch', :aggregate_failures do
          expect(ppu.cpu_read(0x2007, 0x00)).to eq(0x5A)
          expect(ppu.cpu_read(0x2000, 0x00)).to eq(0x5A)
        end
      end

      context 'and v is in the palette' do
        let(:scroll_registers) { Ruby::Nes::Ppu::ScrollRegisters.new(vram_address: 0x3F00) }

        before do
          allow(bus).to receive(:read).with(0x3F00).and_return(0x2C)
          allow(bus).to receive(:read).with(0x2F00).and_return(0x00)
          ppu.cpu_write(0x2002, 0xC0)
        end

        it "returns the colour with the latch's bits 7-6" do
          expect(ppu.cpu_read(0x2007, 0x00)).to eq(0xEC)
        end
      end
    end
  end
end
