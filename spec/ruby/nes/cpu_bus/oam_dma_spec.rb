# frozen_string_literal: true

# OAM DMA (https://www.nesdev.org/wiki/DMA): "OAM DMA copies 256 bytes from a CPU page to PPU OAM via the OAMDATA
# ($2004) register"; "The 256 get/put pairs copy forward from the start of the page"; it "halts the CPU, performs an
# optional alignment cycle, and then gets and puts 256 times, taking 513 or 514 cycles": a $4014 write on a get cycle
# takes 513, one on a put cycle 514. Get cycles are the even CPU cycles, a convention (plan 11, decision 3): "At
# power-on, whether the first CPU cycle is get or put is random."
RSpec.describe Ruby::Nes::CpuBus::OamDma do
  describe '#start' do
    subject(:oam_dma) { described_class.new(bus:, ppu_registers:) }

    let(:bus) { FlatBus.new }
    let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }
    let(:sprite_page) { [0x11, *Array.new(254, 0x00), 0x99] }

    before do
      bus.write_bytes(0x0200, sprite_page)
      bus.write(0x0300, 0x42)
      oam_dma.start(0x02)
    end

    it 'writes the 256 bytes of the page to OAMDATA, from the first to the last', :aggregate_failures do
      expect(ppu_registers).to have_received(:cpu_write).with(0x2004, 0x11).ordered
      expect(ppu_registers).to have_received(:cpu_write).with(0x2004, 0x99).ordered
      expect(ppu_registers).to have_received(:cpu_write).with(0x2004, anything).exactly(256).times
      expect(ppu_registers).not_to have_received(:cpu_write).with(0x2004, 0x42)
    end
  end

  describe '#take_stall_cycles' do
    subject(:oam_dma) { described_class.new(bus:, ppu_registers:) }

    let(:bus) { FlatBus.new }
    let(:ppu_registers) { object_double(Ruby::Nes::CpuBus::Disconnected, cpu_write: nil) }

    context 'when no DMA was started' do
      it 'returns 0' do
        expect(oam_dma.take_stall_cycles(1001)).to eq(0)
      end
    end

    context 'when a DMA was started' do
      before { oam_dma.start(0x02) }

      context 'but its stall was already taken' do
        before { oam_dma.take_stall_cycles(1001) }

        it 'returns 0' do
          expect(oam_dma.take_stall_cycles(1515)).to eq(0)
        end
      end

      context 'and the CPU halts on an odd cycle, so the write was on a get cycle' do
        it 'returns 513' do
          expect(oam_dma.take_stall_cycles(1001)).to eq(513)
        end
      end

      context 'and the CPU halts on an even cycle, so the write was on a put cycle' do
        it 'returns 514' do
          expect(oam_dma.take_stall_cycles(1000)).to eq(514)
        end
      end
    end
  end
end
