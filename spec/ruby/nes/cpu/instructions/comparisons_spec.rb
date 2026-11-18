# frozen_string_literal: true

# Comparisons (https://www.nesdev.org/wiki/Instruction_reference): CMP, CPX and CPY compare a register with the byte at
# the effective address. C is "register >= memory", Z is "register == memory", N is bit 7 of the difference, and
# "comparison does _not_ affect overflow". The register keeps its value.
RSpec.describe Ruby::Nes::Cpu::Instructions::Comparisons do
  describe '#compare_with_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the accumulator is greater than the byte at the address' do
      let(:accumulator) { 0x50 }

      before do
        bus.write(0x0200, 0x30)
        cpu.status.restore(0x82)
      end

      it 'sets carry and clears zero and negative', :aggregate_failures do
        cpu.compare_with_accumulator(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end

      it 'leaves the accumulator unchanged' do
        cpu.compare_with_accumulator(0x0200)
        expect(cpu.accumulator).to eq(0x50)
      end
    end

    context 'when the accumulator equals the byte at the address' do
      let(:accumulator) { 0x30 }

      before { bus.write(0x0200, 0x30) }

      it 'sets carry and zero', :aggregate_failures do
        cpu.compare_with_accumulator(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_zero
      end
    end

    context 'when the accumulator is less than the byte at the address' do
      let(:accumulator) { 0x30 }

      before do
        bus.write(0x0200, 0x50)
        cpu.status.restore(0x01)
      end

      it 'clears carry and sets negative', :aggregate_failures do
        cpu.compare_with_accumulator(0x0200)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).to be_negative
      end
    end

    context 'when the accumulator is greater but the difference has bit 7 set' do
      let(:accumulator) { 0x90 }

      before { bus.write(0x0200, 0x01) }

      it 'sets carry and negative', :aggregate_failures do
        cpu.compare_with_accumulator(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_negative
      end
    end

    context 'when overflow, interrupt disable and decimal are set' do
      let(:accumulator) { 0x50 }

      before do
        bus.write(0x0200, 0x30)
        cpu.status.restore(0x4C)
      end

      it 'leaves them set' do
        cpu.compare_with_accumulator(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#compare_with_index_x' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, index_x:) }

    let(:bus) { FlatBus.new }

    context 'when X is greater than the byte at the address' do
      let(:index_x) { 0x50 }

      before do
        bus.write(0x0200, 0x30)
        cpu.status.restore(0x82)
      end

      it 'sets carry and clears zero and negative', :aggregate_failures do
        cpu.compare_with_index_x(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end

      it 'leaves X unchanged' do
        cpu.compare_with_index_x(0x0200)
        expect(cpu.index_x).to eq(0x50)
      end
    end

    context 'when X equals the byte at the address' do
      let(:index_x) { 0x30 }

      before { bus.write(0x0200, 0x30) }

      it 'sets carry and zero', :aggregate_failures do
        cpu.compare_with_index_x(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_zero
      end
    end

    context 'when X is less than the byte at the address' do
      let(:index_x) { 0x30 }

      before do
        bus.write(0x0200, 0x50)
        cpu.status.restore(0x01)
      end

      it 'clears carry and sets negative', :aggregate_failures do
        cpu.compare_with_index_x(0x0200)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).to be_negative
      end
    end

    context 'when X is greater but the difference has bit 7 set' do
      let(:index_x) { 0x90 }

      before { bus.write(0x0200, 0x01) }

      it 'sets carry and negative', :aggregate_failures do
        cpu.compare_with_index_x(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_negative
      end
    end

    context 'when overflow, interrupt disable and decimal are set' do
      let(:index_x) { 0x50 }

      before do
        bus.write(0x0200, 0x30)
        cpu.status.restore(0x4C)
      end

      it 'leaves them set' do
        cpu.compare_with_index_x(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#compare_with_index_y' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, index_y:) }

    let(:bus) { FlatBus.new }

    context 'when Y is greater than the byte at the address' do
      let(:index_y) { 0x50 }

      before do
        bus.write(0x0200, 0x30)
        cpu.status.restore(0x82)
      end

      it 'sets carry and clears zero and negative', :aggregate_failures do
        cpu.compare_with_index_y(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end

      it 'leaves Y unchanged' do
        cpu.compare_with_index_y(0x0200)
        expect(cpu.index_y).to eq(0x50)
      end
    end

    context 'when Y equals the byte at the address' do
      let(:index_y) { 0x30 }

      before { bus.write(0x0200, 0x30) }

      it 'sets carry and zero', :aggregate_failures do
        cpu.compare_with_index_y(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_zero
      end
    end

    context 'when Y is less than the byte at the address' do
      let(:index_y) { 0x30 }

      before do
        bus.write(0x0200, 0x50)
        cpu.status.restore(0x01)
      end

      it 'clears carry and sets negative', :aggregate_failures do
        cpu.compare_with_index_y(0x0200)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).to be_negative
      end
    end

    context 'when Y is greater but the difference has bit 7 set' do
      let(:index_y) { 0x90 }

      before { bus.write(0x0200, 0x01) }

      it 'sets carry and negative', :aggregate_failures do
        cpu.compare_with_index_y(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_negative
      end
    end

    context 'when overflow, interrupt disable and decimal are set' do
      let(:index_y) { 0x50 }

      before do
        bus.write(0x0200, 0x30)
        cpu.status.restore(0x4C)
      end

      it 'leaves them set' do
        cpu.compare_with_index_y(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end
end
