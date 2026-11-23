# frozen_string_literal: true

# The DMC's memory reader (https://www.nesdev.org/wiki/APU_DMC): "An 8-bit sample buffer" filled "whenever the sample
# buffer is empty and the bytes-remaining counter isn't 0", reading the byte at the sample's address. "DMC DMA halts the
# CPU, performs a dummy cycle and an optional alignment cycle, and then gets once, taking 3 or 4 cycles"; "Load DMAs
# take 3 cycles and reload DMAs take 4" (https://www.nesdev.org/wiki/DMA): a load follows a $4015 write, a reload the
# output unit emptying the buffer (plan 23, decision 2), and the load happens on the write (decision 3). A $4015 write
# with the DMC bit set restarts the sample "only if its bytes-remaining counter is 0" (https://www.nesdev.org/wiki/APU);
# one with the bit clear ends it, and "the DMC will silence when it empties": the buffer keeps its byte. apu_test's
# 7-dmc_basics #19: "There should be a one-byte buffer that's filled immediately if empty".
RSpec.describe Ruby::Nes::Apu::Dmc::MemoryReader do
  describe '#start' do
    context 'when the sample is playing' do
      subject(:reader) do
        described_class.new(sample:, memory:, cpu:).tap { |memory_reader| memory_reader.start(50) }
      end

      let(:sample) { Ruby::Nes::Apu::Dmc::Sample.new(interrupt:).tap { |position| position.length_register = 0x01 } }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }
      let(:memory) { FlatBus.new }
      let(:cpu) { instance_double(Ruby::Nes::Cpu, halt: nil) }

      before { reader.start(60) }

      it 'leaves it where it is', :aggregate_failures do
        expect(sample).to have_attributes(address: 0xC001, bytes_remaining: 16)
        expect(cpu).to have_received(:halt).once
      end
    end

    context 'when the sample has ended' do
      context 'but the buffer still holds a byte' do
        subject(:reader) do
          described_class.new(sample:, memory:, cpu:).tap { |memory_reader| memory_reader.start(50) }
        end

        let(:sample) { Ruby::Nes::Apu::Dmc::Sample.new(interrupt:) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, trigger: nil) }
        let(:memory) { FlatBus.new }
        let(:cpu) { instance_double(Ruby::Nes::Cpu, halt: nil) }

        before { reader.start(60) }

        it 'restarts the sample without fetching', :aggregate_failures do
          expect(sample).to have_attributes(address: 0xC000, bytes_remaining: 1)
          expect(cpu).to have_received(:halt).once
        end
      end

      context 'and the buffer is empty' do
        subject(:reader) { described_class.new(sample:, memory:, cpu:) }

        let(:sample) { Ruby::Nes::Apu::Dmc::Sample.new(interrupt:) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, trigger: nil) }
        let(:memory) { FlatBus.new.tap { |bus| bus.write(0xC000, 0x5A) } }
        let(:cpu) { instance_double(Ruby::Nes::Cpu, halt: nil) }

        before { reader.start(50) }

        it 'restarts the sample and fetches its first byte, halting the CPU 3 cycles', :aggregate_failures do
          expect(cpu).to have_received(:halt).with(3)
          expect(sample).to have_attributes(address: 0xC001, bytes_remaining: 0)
          expect(interrupt).to have_received(:trigger).with(50)
          expect(reader.take_sample(60)).to eq(0x5A)
        end
      end
    end
  end

  describe '#take_sample' do
    context 'when the buffer is empty' do
      subject(:reader) { described_class.new(sample:, memory:, cpu:) }

      let(:sample) { Ruby::Nes::Apu::Dmc::Sample.new(interrupt:) }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }
      let(:memory) { FlatBus.new }
      let(:cpu) { instance_double(Ruby::Nes::Cpu, halt: nil) }

      it 'returns nothing and fetches nothing', :aggregate_failures do
        expect(reader.take_sample(60)).to be_nil
        expect(cpu).not_to have_received(:halt)
      end
    end

    context 'when the buffer holds a byte' do
      context 'but the sample has ended' do
        subject(:reader) do
          described_class.new(sample:, memory:, cpu:).tap { |memory_reader| memory_reader.start(50) }
        end

        let(:sample) { Ruby::Nes::Apu::Dmc::Sample.new(interrupt:) }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag, trigger: nil) }
        let(:memory) { FlatBus.new.tap { |bus| bus.write(0xC000, 0x5A) } }
        let(:cpu) { instance_double(Ruby::Nes::Cpu, halt: nil) }

        it 'returns the byte and leaves the buffer empty', :aggregate_failures do
          expect(reader.take_sample(60)).to eq(0x5A)
          expect(reader.take_sample(70)).to be_nil
          expect(cpu).to have_received(:halt).once
        end
      end

      context 'and the sample is playing' do
        subject(:reader) do
          described_class.new(sample:, memory:, cpu:).tap { |memory_reader| memory_reader.start(50) }
        end

        let(:sample) { Ruby::Nes::Apu::Dmc::Sample.new(interrupt:).tap { |position| position.length_register = 0x01 } }
        let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }
        let(:memory) { FlatBus.new.tap { |bus| bus.write_bytes(0xC000, [0x5A, 0xA5]) } }
        let(:cpu) { instance_double(Ruby::Nes::Cpu, halt: nil) }

        it 'returns the byte and fetches the next one, halting the CPU 4 cycles', :aggregate_failures do
          expect(reader.take_sample(60)).to eq(0x5A)
          expect(cpu).to have_received(:halt).with(4)
          expect(reader.take_sample(70)).to eq(0xA5)
        end
      end
    end
  end

  describe '#stop' do
    context 'when the buffer holds a byte' do
      subject(:reader) do
        described_class.new(sample:, memory:, cpu:).tap { |memory_reader| memory_reader.start(50) }
      end

      let(:sample) { Ruby::Nes::Apu::Dmc::Sample.new(interrupt:).tap { |position| position.length_register = 0x01 } }
      let(:interrupt) { instance_double(Ruby::Nes::Apu::InterruptFlag) }
      let(:memory) { FlatBus.new.tap { |bus| bus.write(0xC000, 0x5A) } }
      let(:cpu) { instance_double(Ruby::Nes::Cpu, halt: nil) }

      it 'ends the sample but keeps the byte', :aggregate_failures do
        reader.stop
        expect(reader).not_to be_active
        expect(reader.take_sample(60)).to eq(0x5A)
      end
    end
  end

  describe '#empty?' do
    context 'when the buffer holds no byte' do
      subject(:reader) { described_class.new(sample:) }

      let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample) }

      it { is_expected.to be_empty }
    end

    context 'when the buffer holds a byte' do
      subject(:reader) { described_class.new(sample:, memory:, cpu:).tap { |dma| dma.start(10) } }

      let(:sample) { instance_double(Ruby::Nes::Apu::Dmc::Sample, active?: true, address: 0xC000, advance: nil) }
      let(:memory) { instance_double(Ruby::Nes::CpuBus, read_for_dma: 0x55) }
      let(:cpu) { instance_double(Ruby::Nes::Cpu, halt: nil) }

      it { is_expected.not_to be_empty }
    end
  end
end
