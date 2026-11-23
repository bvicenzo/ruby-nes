# frozen_string_literal: true

# The DMC's output unit (https://www.nesdev.org/wiki/APU_DMC): an 8-bit shift register "loaded with the content from
# sample buffer, shifted as the clocking happens", driving the 7-bit output level. On each timer clock its bit 0
# decides: "If it is 0 and the current output level is higher than 1, decrement the output level by 2", "If it is 1 and
# the current output level is below 126, increment the output level by 2"; then it shifts right. Once "all eight bits in
# the shift register is spent", a full buffer starts a new byte and empties the buffer; an empty one leaves "the output
# unit is inactive for the next eight timer clocks". $4011 is the "Direct counter load", 7 bits; after reset "[$4011] &=
# 1" (https://www.nesdev.org/wiki/CPU_power_up_state). No page gives its state at power: by convention it starts silent,
# eight clocks from its first byte (plan 23, decision 9).
RSpec.describe Ruby::Nes::Apu::Dmc::OutputUnit do
  describe '#clock' do
    context 'when the unit is silent' do
      subject(:output_unit) { described_class.new(reader:).tap { |unit| unit.direct_load(64) } }

      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader) }

      it 'keeps the output level' do
        output_unit.clock(10)
        expect(output_unit.output).to eq(64)
      end
    end

    context 'when it plays a byte' do
      context 'and the bit is 1' do
        context 'but the level is above 125' do
          subject(:output_unit) do
            described_class.new(reader:).tap do |unit|
              unit.direct_load(126)
              8.times { |cycle| unit.clock(cycle) }
            end
          end

          let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, take_sample: 0xFF) }

          it 'keeps the level' do
            output_unit.clock(10)
            expect(output_unit.output).to eq(126)
          end
        end

        context 'and the level is 125 or below' do
          subject(:output_unit) do
            described_class.new(reader:).tap do |unit|
              unit.direct_load(125)
              8.times { |cycle| unit.clock(cycle) }
            end
          end

          let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, take_sample: 0xFF) }

          it 'raises it by 2' do
            output_unit.clock(10)
            expect(output_unit.output).to eq(127)
          end
        end
      end

      context 'and the bit is 0' do
        context 'but the level is below 2' do
          subject(:output_unit) do
            described_class.new(reader:).tap do |unit|
              unit.direct_load(1)
              8.times { |cycle| unit.clock(cycle) }
            end
          end

          let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, take_sample: 0x00) }

          it 'keeps the level' do
            output_unit.clock(10)
            expect(output_unit.output).to eq(1)
          end
        end

        context 'and the level is 2 or above' do
          subject(:output_unit) do
            described_class.new(reader:).tap do |unit|
              unit.direct_load(2)
              8.times { |cycle| unit.clock(cycle) }
            end
          end

          let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, take_sample: 0x00) }

          it 'lowers it by 2' do
            output_unit.clock(10)
            expect(output_unit.output).to eq(0)
          end
        end
      end
    end

    context 'when it spends the eighth bit' do
      context 'and the sample buffer is empty' do
        subject(:output_unit) do
          described_class.new(reader:).tap do |unit|
            unit.direct_load(64)
            7.times { |cycle| unit.clock(cycle) }
          end
        end

        let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, take_sample: nil) }

        it 'stays silent for the next eight clocks', :aggregate_failures do
          output_unit.clock(7)
          8.times { |cycle| output_unit.clock(8 + cycle) }
          expect(output_unit.output).to eq(64)
          expect(reader).to have_received(:take_sample).with(7).ordered
          expect(reader).to have_received(:take_sample).with(15).ordered
        end
      end

      context 'and the sample buffer holds a byte' do
        subject(:output_unit) do
          described_class.new(reader:).tap do |unit|
            unit.direct_load(64)
            7.times { |cycle| unit.clock(cycle) }
          end
        end

        let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, take_sample: 0b0000_0101) }

        it 'plays its bits from bit 0 up', :aggregate_failures do
          output_unit.clock(7)
          expect(reader).to have_received(:take_sample).with(7)
          output_unit.clock(8)
          expect(output_unit.output).to eq(66)
          output_unit.clock(9)
          expect(output_unit.output).to eq(64)
          output_unit.clock(10)
          expect(output_unit.output).to eq(66)
        end
      end
    end
  end

  describe '#direct_load' do
    context 'when bit 7 of the value is set' do
      subject(:output_unit) { described_class.new(reader:) }

      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader) }

      it 'sets the level to its low 7 bits' do
        output_unit.direct_load(0xFF)
        expect(output_unit.output).to eq(127)
      end
    end
  end

  describe '#reset' do
    context 'when the level is odd' do
      subject(:output_unit) { described_class.new(reader:).tap { |unit| unit.direct_load(0x45) } }

      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader) }

      it 'keeps only bit 0 of the level' do
        output_unit.reset
        expect(output_unit.output).to eq(1)
      end
    end
  end

  # The clock that ends the output cycle starts the next one, which takes the reader's byte (plan 29: the DMC's next
  # fetch).
  describe '#clocks_to_output_cycle' do
    subject(:output_unit) { described_class.new(reader:).tap { |unit| 3.times { |cycle| unit.clock(cycle) } } }

    let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader) }

    it 'answers the clocks left in the output cycle' do
      expect(output_unit.clocks_to_output_cycle).to eq(5)
    end
  end

  describe '#silent?' do
    context 'when the output cycle has no byte' do
      subject(:output_unit) { described_class.new(reader:) }

      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader) }

      it { is_expected.to be_silent }
    end

    context 'when the output cycle plays a byte' do
      subject(:output_unit) { described_class.new(reader:).tap { |unit| 8.times { |cycle| unit.clock(cycle) } } }

      let(:reader) { instance_double(Ruby::Nes::Apu::Dmc::MemoryReader, take_sample: 0x55) }

      it { is_expected.not_to be_silent }
    end
  end
end
