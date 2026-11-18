# frozen_string_literal: true

# Logic instructions (https://www.nesdev.org/wiki/Instruction_reference): AND, EOR and ORA combine A with the byte at
# the effective address, keep the result in A and set Z ("result == 0") and N ("result bit 7"). BIT: "Bits 7 and 6 of
# the memory value are loaded directly into the negative and overflow flags", and Z comes from "the accumulator AND
# memory value"; A is not changed. A = $CC and memory = $AA tell the three operations apart: AND $88, EOR $66, ORA $EE.
RSpec.describe Ruby::Nes::Cpu::Instructions::Logic do
  describe '#and_with_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the accumulator is $CC and the byte at the address is $AA' do
      let(:accumulator) { 0xCC }

      before do
        bus.write(0x0200, 0xAA)
        cpu.status.restore(0x02)
      end

      it 'leaves $88 in the accumulator' do
        cpu.and_with_accumulator(0x0200)
        expect(cpu.accumulator).to eq(0x88)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.and_with_accumulator(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when the result is $00' do
      let(:accumulator) { 0x0F }

      before do
        bus.write(0x0200, 0xF0)
        cpu.status.restore(0x80)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.and_with_accumulator(0x0200)
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:accumulator) { 0x01 }

      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x4D)
      end

      it 'leaves them set' do
        cpu.and_with_accumulator(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#exclusive_or_with_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the accumulator is $CC and the byte at the address is $AA' do
      let(:accumulator) { 0xCC }

      before do
        bus.write(0x0200, 0xAA)
        cpu.status.restore(0x82)
      end

      it 'leaves $66 in the accumulator' do
        cpu.exclusive_or_with_accumulator(0x0200)
        expect(cpu.accumulator).to eq(0x66)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.exclusive_or_with_accumulator(0x0200)
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the result is $00' do
      let(:accumulator) { 0x5A }

      before do
        bus.write(0x0200, 0x5A)
        cpu.status.restore(0x80)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.exclusive_or_with_accumulator(0x0200)
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:accumulator) { 0x01 }

      before do
        bus.write(0x0200, 0x00)
        cpu.status.restore(0x4D)
      end

      it 'leaves them set' do
        cpu.exclusive_or_with_accumulator(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#or_with_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the accumulator is $CC and the byte at the address is $AA' do
      let(:accumulator) { 0xCC }

      before do
        bus.write(0x0200, 0xAA)
        cpu.status.restore(0x02)
      end

      it 'leaves $EE in the accumulator' do
        cpu.or_with_accumulator(0x0200)
        expect(cpu.accumulator).to eq(0xEE)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.or_with_accumulator(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when the result is $00' do
      let(:accumulator) { 0x00 }

      before do
        bus.write(0x0200, 0x00)
        cpu.status.restore(0x80)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.or_with_accumulator(0x0200)
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:accumulator) { 0x01 }

      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x4D)
      end

      it 'leaves them set' do
        cpu.or_with_accumulator(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#test_bits' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the accumulator AND the byte at the address is $00' do
      let(:accumulator) { 0x0F }

      before { bus.write(0x0200, 0x30) }

      it 'sets zero' do
        cpu.test_bits(0x0200)
        expect(cpu.status).to be_zero
      end

      it 'leaves the accumulator unchanged' do
        cpu.test_bits(0x0200)
        expect(cpu.accumulator).to eq(0x0F)
      end
    end

    context 'when the accumulator AND the byte at the address is not $00' do
      let(:accumulator) { 0x01 }

      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x02)
      end

      it 'clears zero' do
        cpu.test_bits(0x0200)
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when the byte at the address has bits 7 and 6 set and the accumulator is $00' do
      let(:accumulator) { 0x00 }

      before { bus.write(0x0200, 0xC0) }

      it 'sets negative and overflow', :aggregate_failures do
        cpu.test_bits(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).to be_overflow
      end
    end

    context 'when the byte at the address has bits 7 and 6 clear and the accumulator is $FF' do
      let(:accumulator) { 0xFF }

      before do
        bus.write(0x0200, 0x3F)
        cpu.status.restore(0xC0)
      end

      it 'clears negative and overflow', :aggregate_failures do
        cpu.test_bits(0x0200)
        expect(cpu.status).not_to be_negative
        expect(cpu.status).not_to be_overflow
      end
    end

    context 'when carry, interrupt disable and decimal are set' do
      let(:accumulator) { 0x01 }

      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x0D)
      end

      it 'leaves them set' do
        cpu.test_bits(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x2D)
      end
    end
  end
end
