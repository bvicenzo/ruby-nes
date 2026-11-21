# frozen_string_literal: true

RSpec.describe Ruby::Nes::CpuBus do
  describe '#read' do
    context 'when no device is connected' do
      subject(:bus) { described_class.new }

      before do
        bus.write(0x0000, 0x42)
        bus.read(0x0000)
      end

      it 'answers every device range with the data bus value', :aggregate_failures do
        expect(bus.read(0x2000)).to eq(0x42)
        expect(bus.read(0x4000)).to eq(0x42)
        expect(bus.read(0x8000)).to eq(0x42)
      end
    end

    context 'when the address is in internal RAM' do
      subject(:bus) { described_class.new }

      before do
        bus.write(0x0000, 0x11)
        bus.write(0x07FF, 0x22)
      end

      context 'and it is $07FF' do
        it 'returns the byte stored at $07FF' do
          expect(bus.read(0x07FF)).to eq(0x22)
        end
      end

      context 'and it is $0800' do
        it 'returns the byte stored at $0000' do
          expect(bus.read(0x0800)).to eq(0x11)
        end
      end

      context 'and it is $1FFF' do
        it 'returns the byte stored at $07FF' do
          expect(bus.read(0x1FFF)).to eq(0x22)
        end
      end
    end

    context 'when the address is in the PPU registers' do
      subject(:bus) { described_class.new(ppu_registers:) }

      let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected) }

      context 'and it is $2000' do
        before { allow(ppu_registers).to receive(:cpu_read).with(0x2000, 0x00).and_return(0x21) }

        it 'returns what the PPU registers answer for $2000' do
          expect(bus.read(0x2000)).to eq(0x21)
        end
      end

      context 'and it is $2007' do
        before { allow(ppu_registers).to receive(:cpu_read).with(0x2007, 0x00).and_return(0x27) }

        it 'returns what the PPU registers answer for $2007' do
          expect(bus.read(0x2007)).to eq(0x27)
        end
      end

      context 'and it is $2008' do
        before { allow(ppu_registers).to receive(:cpu_read).with(0x2000, 0x00).and_return(0x21) }

        it 'returns what the PPU registers answer for $2000' do
          expect(bus.read(0x2008)).to eq(0x21)
        end
      end

      context 'and it is $3FFF' do
        before { allow(ppu_registers).to receive(:cpu_read).with(0x2007, 0x00).and_return(0x27) }

        it 'returns what the PPU registers answer for $2007' do
          expect(bus.read(0x3FFF)).to eq(0x27)
        end
      end

      context 'and a byte was read before' do
        before do
          allow(ppu_registers).to receive(:cpu_read).with(0x2002, 0x42).and_return(0x80)
          bus.write(0x0000, 0x42)
          bus.read(0x0000)
        end

        it 'hands that byte to the PPU registers as the data bus' do
          expect(bus.read(0x2002)).to eq(0x80)
        end
      end
    end

    context 'when the address is in the APU registers' do
      subject(:bus) { described_class.new(apu_registers:) }

      let(:apu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected) }

      context 'and it is $4000' do
        before { allow(apu_registers).to receive(:cpu_read).with(0x4000, 0x00).and_return(0x40) }

        it 'returns what the APU registers answer for $4000' do
          expect(bus.read(0x4000)).to eq(0x40)
        end
      end

      context 'and it is $4014' do
        before { allow(apu_registers).to receive(:cpu_read).with(0x4014, 0x00).and_return(0x40) }

        it 'returns what the APU registers answer for $4014' do
          expect(bus.read(0x4014)).to eq(0x40)
        end
      end

      context 'and it is $4015' do
        before { allow(apu_registers).to receive(:cpu_read).with(0x4015, 0x00).and_return(0x41) }

        it 'returns what the APU registers answer for $4015' do
          expect(bus.read(0x4015)).to eq(0x41)
        end
      end

      context 'and a byte was read before' do
        before do
          allow(apu_registers).to receive(:cpu_read).with(0x4015, 0x42).and_return(0x41)
          bus.write(0x0000, 0x42)
          bus.read(0x0000)
        end

        it 'hands that byte to the APU registers as the data bus' do
          expect(bus.read(0x4015)).to eq(0x41)
        end
      end

      # $4015 "is internal to the CPU and so the external CPU data bus is disconnected when reading it", so the read
      # "does not affect open bus" (https://www.nesdev.org/wiki/APU); the rest of the slot is open bus already (plan 22,
      # decision 2).
      context 'and the APU registers answered a read' do
        before do
          allow(apu_registers).to receive(:cpu_read).with(0x4015, 0x42).and_return(0x41)
          bus.write(0x0000, 0x42)
          bus.read(0x0000)
          bus.read(0x4015)
        end

        # $4018, which no device answers, reads the data bus back.
        it 'leaves the data bus as it was' do
          expect(bus.read(0x4018)).to eq(0x42)
        end
      end
    end

    # "$4016 reads only from controller port 1, and $4017 reads only from controller port 2"
    # (https://www.nesdev.org/wiki/Controller_reading); plan 15, decision 1 gives them a slot of their own.
    context 'when the address is in the controller ports' do
      subject(:bus) { described_class.new(controller_ports:) }

      let(:controller_ports) { object_double(Ruby::Nes::CpuBus::Disconnected) }

      context 'and it is $4016' do
        before { allow(controller_ports).to receive(:cpu_read).with(0x4016, 0x00).and_return(0x41) }

        it 'returns what the controller ports answer for $4016' do
          expect(bus.read(0x4016)).to eq(0x41)
        end
      end

      context 'and it is $4017' do
        before { allow(controller_ports).to receive(:cpu_read).with(0x4017, 0x00).and_return(0x40) }

        it 'returns what the controller ports answer for $4017' do
          expect(bus.read(0x4017)).to eq(0x40)
        end
      end

      context 'and a byte was read before' do
        before do
          allow(controller_ports).to receive(:cpu_read).with(0x4016, 0x42).and_return(0x41)
          bus.write(0x0000, 0x42)
          bus.read(0x0000)
        end

        it 'hands that byte to the controller ports as the data bus' do
          expect(bus.read(0x4016)).to eq(0x41)
        end
      end
    end

    context 'when the address is in the disabled test range' do
      subject(:bus) { described_class.new(mapper:) }

      let(:mapper) { object_double(Ruby::Nes::CpuBus::Disconnected) }

      context 'and nothing was read before' do
        it 'returns zero' do
          expect(bus.read(0x4018)).to eq(0x00)
        end
      end

      context 'and a byte was read before' do
        before do
          bus.write(0x0000, 0x42)
          bus.read(0x0000)
        end

        context 'and the address is $4018' do
          it 'returns the byte read before' do
            expect(bus.read(0x4018)).to eq(0x42)
          end
        end

        context 'and the address is $401F' do
          it 'returns the byte read before' do
            expect(bus.read(0x401F)).to eq(0x42)
          end
        end

        context 'and a device answered a later read' do
          before do
            allow(mapper).to receive(:cpu_read).with(0x8000, 0x42).and_return(0xA9)
            bus.read(0x8000)
          end

          it 'returns the byte the device answered' do
            expect(bus.read(0x4018)).to eq(0xA9)
          end
        end

        context 'but a byte was written after that read' do
          before { bus.write(0x0001, 0x77) }

          it 'returns the byte read before' do
            expect(bus.read(0x4018)).to eq(0x42)
          end
        end
      end
    end

    context 'when the address is in the cartridge space' do
      subject(:bus) { described_class.new(mapper:) }

      let(:mapper) { object_double(Ruby::Nes::CpuBus::Disconnected) }

      context 'and it is $4020' do
        before { allow(mapper).to receive(:cpu_read).with(0x4020, 0x00).and_return(0x60) }

        it 'returns what the board answers for $4020' do
          expect(bus.read(0x4020)).to eq(0x60)
        end
      end

      context 'and it is $FFFF' do
        before { allow(mapper).to receive(:cpu_read).with(0xFFFF, 0x00).and_return(0xC0) }

        it 'returns what the board answers for $FFFF' do
          expect(bus.read(0xFFFF)).to eq(0xC0)
        end
      end

      context 'and a byte was read before' do
        before do
          allow(mapper).to receive(:cpu_read).with(0x5000, 0x42).and_return(0x42)
          bus.write(0x0000, 0x42)
          bus.read(0x0000)
        end

        it 'hands that byte to the board as the data bus' do
          expect(bus.read(0x5000)).to eq(0x42)
        end
      end
    end
  end

  # OAM DMA reads (https://www.nesdev.org/wiki/DMA): the 2A03's registers answer "bits 4-0 from the 2A03 address bus and
  # bits 15-5 from the 6502 core", and "The 6502 core keeps the same address while halted"; halted on an opcode fetch,
  # the core is never in $4000-$401F, so a DMA read there reaches none of them and the bus keeps its value (open bus).
  # Every other address is read as the CPU reads it.
  describe '#read_for_dma' do
    context 'when the address is in the 2A03 registers' do
      subject(:bus) { described_class.new(apu_registers:, controller_ports:) }

      let(:apu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected) }
      let(:controller_ports) { object_double(Ruby::Nes::CpuBus::Disconnected) }

      before do
        allow(apu_registers).to receive(:cpu_read)
        allow(controller_ports).to receive(:cpu_read)
        bus.write(0x0000, 0x42)
        bus.read(0x0000)
      end

      context 'and it is $4000' do
        it 'returns the data bus value, reaching no device', :aggregate_failures do
          expect(bus.read_for_dma(0x4000)).to eq(0x42)
          expect(apu_registers).not_to have_received(:cpu_read)
        end
      end

      context 'and it is $4016' do
        it 'returns the data bus value, reaching no device', :aggregate_failures do
          expect(bus.read_for_dma(0x4016)).to eq(0x42)
          expect(controller_ports).not_to have_received(:cpu_read)
        end
      end

      context 'and it is $401F' do
        it 'returns the data bus value' do
          expect(bus.read_for_dma(0x401F)).to eq(0x42)
        end
      end
    end

    context 'when the address is outside them' do
      subject(:bus) { described_class.new(mapper:, ppu_registers:) }

      let(:mapper) { object_double(Ruby::Nes::CpuBus::Disconnected) }
      let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected) }

      context 'and it is $3FFF' do
        before { allow(ppu_registers).to receive(:cpu_read).with(0x2007, 0x00).and_return(0x37) }

        it 'returns what the PPU registers answer for $2007' do
          expect(bus.read_for_dma(0x3FFF)).to eq(0x37)
        end
      end

      context 'and it is $4020' do
        before { allow(mapper).to receive(:cpu_read).with(0x4020, 0x00).and_return(0x5A) }

        it 'returns what the mapper answers for $4020' do
          expect(bus.read_for_dma(0x4020)).to eq(0x5A)
        end
      end
    end
  end

  describe '#write' do
    context 'when the address is in internal RAM' do
      subject(:bus) { described_class.new }

      context 'and it is $0000' do
        before { bus.write(0x0000, 0x11) }

        it 'is visible at all four mirrors', :aggregate_failures do
          expect(bus.read(0x0000)).to eq(0x11)
          expect(bus.read(0x0800)).to eq(0x11)
          expect(bus.read(0x1000)).to eq(0x11)
          expect(bus.read(0x1800)).to eq(0x11)
        end
      end

      context 'and it is $1FFF' do
        before { bus.write(0x1FFF, 0x22) }

        it 'is visible at all four mirrors', :aggregate_failures do
          expect(bus.read(0x07FF)).to eq(0x22)
          expect(bus.read(0x0FFF)).to eq(0x22)
          expect(bus.read(0x17FF)).to eq(0x22)
          expect(bus.read(0x1FFF)).to eq(0x22)
        end
      end
    end

    context 'when the address is in the PPU registers' do
      subject(:bus) { described_class.new(ppu_registers:) }

      let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

      context 'and it is $2000' do
        before { bus.write(0x2000, 0x80) }

        it 'hands the byte to the PPU registers at $2000' do
          expect(ppu_registers).to have_received(:cpu_write).with(0x2000, 0x80)
        end
      end

      context 'and it is $2008' do
        before { bus.write(0x2008, 0x80) }

        it 'hands the byte to the PPU registers at $2000' do
          expect(ppu_registers).to have_received(:cpu_write).with(0x2000, 0x80)
        end
      end

      context 'and it is $3FFF' do
        before { bus.write(0x3FFF, 0x80) }

        it 'hands the byte to the PPU registers at $2007' do
          expect(ppu_registers).to have_received(:cpu_write).with(0x2007, 0x80)
        end
      end
    end

    context 'when the address is in the APU registers' do
      subject(:bus) { described_class.new(ppu_registers:, apu_registers:, controller_ports:) }

      let(:apu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }
      let(:controller_ports) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

      context 'and it is $4000' do
        let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

        before { bus.write(0x4000, 0x30) }

        it 'hands the byte to the APU registers at $4000' do
          expect(apu_registers).to have_received(:cpu_write).with(0x4000, 0x30)
        end
      end

      # OAMDMA (https://www.nesdev.org/wiki/PPU_registers): "256 pairs of a read from CPU memory and a write to OAMDATA"
      # (plan 11, decision 2: the CPU bus owns the DMA unit). OAMDATA "Writes will increment OAMADDR after the write", so
      # the page lands from OAMADDR on and wraps around OAM.
      context 'and it is $4014' do
        context 'and any device answers the PPU registers' do
          let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

          before do
            bus.write(0x0200, 0x11)
            bus.write(0x02FF, 0x99)
            bus.write(0x4014, 0x02)
          end

          it 'copies the page to OAMDATA and hands nothing to the APU registers', :aggregate_failures do
            expect(ppu_registers).to have_received(:cpu_write).with(0x2004, 0x11).ordered
            expect(ppu_registers).to have_received(:cpu_write).with(0x2004, 0x99).ordered
            expect(ppu_registers).to have_received(:cpu_write).with(0x2004, anything).exactly(256).times
            expect(apu_registers).not_to have_received(:cpu_write)
          end
        end

        context 'and the PPU answers them with OAMADDR at $F0' do
          let(:ppu_registers) { Ruby::Nes::Ppu.new(bus: instance_double(Ruby::Nes::PpuBus), oam:) }
          let(:oam) { Ruby::Nes::Ppu::Oam.new(address: 0xF0) }

          before do
            bus.write(0x0200, 0x11)
            bus.write(0x020F, 0x22)
            bus.write(0x0210, 0x33)
            bus.write(0x02FF, 0x99)
            bus.write(0x4014, 0x02)
          end

          it 'fills OAM from $F0, wrapping past $FF back to $EF', :aggregate_failures do
            oam.address = 0xF0
            expect(oam.read).to eq(0x11)
            oam.address = 0xFF
            expect(oam.read).to eq(0x22)
            oam.address = 0x00
            expect(oam.read).to eq(0x33)
            oam.address = 0xEF
            expect(oam.read).to eq(0x99)
          end
        end

        # The 2A03 decodes its registers from "bits 4-0 from the 2A03 address bus and bits 15-5 from the 6502 core", and
        # "The 6502 core keeps the same address while halted" (https://www.nesdev.org/wiki/DMA): halted on the fetch
        # after the $4014 write, the core is not reading $4000-$401F, so a DMA from page $40 reaches no 2A03 register.
        context 'and the page is $40' do
          let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

          before do
            allow(apu_registers).to receive(:cpu_read)
            allow(controller_ports).to receive(:cpu_read)
            bus.write(0x0000, 0x42)
            bus.read(0x0000)
            bus.write(0x4014, 0x40)
          end

          it 'copies the data bus value, leaving the APU registers and controller ports unread', :aggregate_failures do
            expect(ppu_registers).to have_received(:cpu_write).with(0x2004, 0x42).exactly(256).times
            expect(apu_registers).not_to have_received(:cpu_read)
            expect(controller_ports).not_to have_received(:cpu_read)
          end
        end
      end

      context 'and it is $4015' do
        let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

        before { bus.write(0x4015, 0x0F) }

        it 'hands the byte to the APU registers at $4015, not to the controller ports', :aggregate_failures do
          expect(apu_registers).to have_received(:cpu_write).with(0x4015, 0x0F)
          expect(controller_ports).not_to have_received(:cpu_write)
        end
      end

      # $4017 is read from controller port 2 but written to the APU frame counter (https://www.nesdev.org/wiki/APU).
      context 'and it is $4017' do
        let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

        before { bus.write(0x4017, 0x40) }

        it 'hands the byte to the APU registers at $4017, not to the controller ports', :aggregate_failures do
          expect(apu_registers).to have_received(:cpu_write).with(0x4017, 0x40)
          expect(controller_ports).not_to have_received(:cpu_write)
        end
      end
    end

    # "Writing 1 to $4016 causes the register to fill its parallel inputs from the buttons currently held"
    # (https://www.nesdev.org/wiki/Controller_reading).
    context 'when the address is the controller strobe' do
      subject(:bus) { described_class.new(apu_registers:, controller_ports:) }

      let(:apu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }
      let(:controller_ports) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

      before { bus.write(0x4016, 0x01) }

      it 'hands the byte to the controller ports at $4016, not to the APU registers', :aggregate_failures do
        expect(controller_ports).to have_received(:cpu_write).with(0x4016, 0x01)
        expect(apu_registers).not_to have_received(:cpu_write)
      end
    end

    context 'when the address is in the disabled test range' do
      subject(:bus) { described_class.new(mapper:, ppu_registers:, apu_registers:, controller_ports:) }

      let(:mapper) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }
      let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }
      let(:apu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }
      let(:controller_ports) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

      context 'and it is $4018' do
        before { bus.write(0x4018, 0x77) }

        it 'reaches no device', :aggregate_failures do
          expect(mapper).not_to have_received(:cpu_write)
          expect(ppu_registers).not_to have_received(:cpu_write)
          expect(apu_registers).not_to have_received(:cpu_write)
          expect(controller_ports).not_to have_received(:cpu_write)
        end
      end

      context 'and it is $401F' do
        before { bus.write(0x401F, 0x77) }

        it 'reaches no device', :aggregate_failures do
          expect(mapper).not_to have_received(:cpu_write)
          expect(ppu_registers).not_to have_received(:cpu_write)
          expect(apu_registers).not_to have_received(:cpu_write)
          expect(controller_ports).not_to have_received(:cpu_write)
        end
      end
    end

    context 'when the address is in the cartridge space' do
      subject(:bus) { described_class.new(mapper:) }

      let(:mapper) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

      context 'and it is $4020' do
        before { bus.write(0x4020, 0x60) }

        it 'hands the byte to the board at $4020' do
          expect(mapper).to have_received(:cpu_write).with(0x4020, 0x60)
        end
      end

      context 'and it is $FFFF' do
        before { bus.write(0xFFFF, 0xC0) }

        it 'hands the byte to the board at $FFFF' do
          expect(mapper).to have_received(:cpu_write).with(0xFFFF, 0xC0)
        end
      end
    end
  end

  # OAM DMA stalls the CPU "513 or 514 cycles" (https://www.nesdev.org/wiki/DMA); the parity rule is CpuBus::OamDma's.
  describe '#take_stall_cycles' do
    subject(:bus) { described_class.new(ppu_registers:) }

    let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

    context 'when no OAM DMA was started' do
      it 'returns 0' do
        expect(bus.take_stall_cycles(1001)).to eq(0)
      end
    end

    context 'when $4014 was written' do
      before { bus.write(0x4014, 0x02) }

      it 'returns the OAM DMA stall' do
        expect(bus.take_stall_cycles(1001)).to eq(513)
      end
    end
  end
end
