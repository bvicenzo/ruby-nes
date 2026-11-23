# frozen_string_literal: true

# PPU memory map (https://www.nesdev.org/wiki/PPU_memory_map): $0000-$1FFF pattern tables on the cartridge,
# $2000-$2FFF nametables and their $3000-$3EFF mirror, $3F00-$3F1F palette RAM and its mirrors up to $3FFF.
RSpec.describe Ruby::Nes::PpuBus do
  describe '#read' do
    subject(:bus) { described_class.new(mapper:) }

    context 'when the address is in the pattern tables' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

      context 'and it is $0000' do
        before { allow(mapper).to receive(:ppu_read).with(0x0000).and_return(0x5A) }

        it 'returns what the mapper answers for $0000' do
          expect(bus.read(0x0000)).to eq(0x5A)
        end
      end

      context 'and it is $1FFF' do
        before { allow(mapper).to receive(:ppu_read).with(0x1FFF).and_return(0xA5) }

        it 'returns what the mapper answers for $1FFF' do
          expect(bus.read(0x1FFF)).to eq(0xA5)
        end
      end
    end

    context 'when the address is in the nametables' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

      context 'and it is $2000' do
        before { bus.write(0x2400, 0x11) }

        it 'returns the byte the mirroring shares with $2400' do
          expect(bus.read(0x2000)).to eq(0x11)
        end
      end

      context 'and it is $3EFF' do
        before { bus.write(0x2EFF, 0x22) }

        it 'returns the byte written at $2EFF' do
          expect(bus.read(0x3EFF)).to eq(0x22)
        end
      end
    end

    context 'when the address is in palette RAM' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

      context 'and it is $3F00' do
        before { bus.write(0x3F10, 0x0F) }

        it 'returns the colour shared with $3F10' do
          expect(bus.read(0x3F00)).to eq(0x0F)
        end
      end

      context 'and it is $3FFF' do
        before { bus.write(0x3F1F, 0x30) }

        it 'returns the colour written at $3F1F' do
          expect(bus.read(0x3FFF)).to eq(0x30)
        end
      end
    end
  end

  describe '#write' do
    subject(:bus) { described_class.new(mapper:) }

    context 'when the address is in the pattern tables' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, ppu_write: nil, mirroring: :horizontal, :nametables= => nil) }

      context 'and it is $0000' do
        before { bus.write(0x0000, 0x5A) }

        it 'hands the byte to the mapper' do
          expect(mapper).to have_received(:ppu_write).with(0x0000, 0x5A)
        end
      end

      context 'and it is $1FFF' do
        before { bus.write(0x1FFF, 0xA5) }

        it 'hands the byte to the mapper' do
          expect(mapper).to have_received(:ppu_write).with(0x1FFF, 0xA5)
        end
      end
    end

    context 'when the address is in the nametables' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, ppu_write: nil, :nametables= => nil) }

      context 'and it is $2000' do
        before { bus.write(0x2000, 0x11) }

        it 'is read at $2400, which the mirroring shares', :aggregate_failures do
          expect(bus.read(0x2400)).to eq(0x11)
          expect(mapper).not_to have_received(:ppu_write)
        end
      end

      context 'and it is $3EFF' do
        before { bus.write(0x3EFF, 0x22) }

        it 'is read at $2EFF' do
          expect(bus.read(0x2EFF)).to eq(0x22)
        end
      end
    end

    context 'when the address is in palette RAM' do
      let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

      context 'and it is $3F00' do
        before { bus.write(0x3F00, 0x0F) }

        it 'is read at $3F10, which shares it' do
          expect(bus.read(0x3F10)).to eq(0x0F)
        end
      end

      context 'and it is $3FFF' do
        before { bus.write(0x3FFF, 0xFF) }

        it 'is read at $3F1F as a 6-bit colour' do
          expect(bus.read(0x3F1F)).to eq(0x3F)
        end
      end
    end
  end

  describe '#place_address' do
    subject(:bus) { described_class.new(mapper:) }

    let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, ppu_address: nil, mirroring: :horizontal, :nametables= => nil) }

    before { bus.place_address(0x1000) }

    it 'shows the address to the mapper' do
      expect(mapper).to have_received(:ppu_address).with(0x1000)
    end
  end

  describe '#earliest_irq_cycle' do
    subject(:bus) { described_class.new(mapper:) }

    let(:mapper) { instance_double(Ruby::Nes::Mappers::Mmc3, earliest_irq_cycle: 640, mirroring: :horizontal, :nametables= => nil) }

    it "answers the board's earliest IRQ cycle" do
      expect(bus.earliest_irq_cycle(600)).to eq(640)
    end
  end

  # The renderer's picture reads the colours straight from palette RAM, without the bus (plan 25, decision 7).
  describe '#palette_ram' do
    subject(:bus) { described_class.new(mapper:) }

    let(:mapper) { instance_double(Ruby::Nes::Mappers::Nrom, mirroring: :horizontal, :nametables= => nil) }

    before { bus.write(0x3F0D, 0x2C) }

    it 'is the palette RAM the bus reads and writes at $3F00-$3FFF' do
      expect(bus.palette_ram.read(0x3F0D)).to eq(0x2C)
    end
  end
end
