# frozen_string_literal: true

# Arithmetic (https://www.nesdev.org/wiki/Instruction_reference). ADC adds A, the byte at the effective address and C;
# C is set when the result "overflowed past $FF", V is `(result ^ A) & (result ^ memory) & $80` ("If the result's sign
# is different from both A's and memory's"), Z and N come from the result. SBC "subtracts 1 more when carry is
# _clear_" and its V is `(result ^ A) & (result ^ ~memory) & $80`: it is ADC with the operand inverted. Decimal mode
# "is permanently disabled on the NES' 2A03 CPU. However, the flag itself still functions" (CLD and SED sections).
RSpec.describe Ruby::Nes::Cpu::Instructions::Arithmetic do
  describe '#add_with_carry' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the carry is clear' do
      context 'and the sum is $30' do
        let(:accumulator) { 0x10 }

        before do
          bus.write(0x0200, 0x20)
          cpu.status.restore(0xC2)
        end

        it 'leaves $30 in the accumulator' do
          cpu.add_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x30)
        end

        it 'clears carry, overflow, zero and negative', :aggregate_failures do
          cpu.add_with_carry(0x0200)
          expect(cpu.status).not_to be_carry
          expect(cpu.status).not_to be_overflow
          expect(cpu.status).not_to be_zero
          expect(cpu.status).not_to be_negative
        end
      end

      context 'and the sum is exactly $FF' do
        let(:accumulator) { 0xF0 }

        before do
          bus.write(0x0200, 0x0F)
          cpu.status.restore(0x00)
        end

        it 'leaves $FF in the accumulator' do
          cpu.add_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0xFF)
        end

        it 'clears carry and sets negative', :aggregate_failures do
          cpu.add_with_carry(0x0200)
          expect(cpu.status).not_to be_carry
          expect(cpu.status).to be_negative
        end
      end

      context 'and the sum is exactly $100' do
        let(:accumulator) { 0xFF }

        before do
          bus.write(0x0200, 0x01)
          cpu.status.restore(0x40)
        end

        it 'leaves $00 in the accumulator' do
          cpu.add_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x00)
        end

        it 'sets carry and zero and clears overflow', :aggregate_failures do
          cpu.add_with_carry(0x0200)
          expect(cpu.status).to be_carry
          expect(cpu.status).to be_zero
          expect(cpu.status).not_to be_overflow
        end
      end

      context 'and two positive bytes sum past $7F' do
        let(:accumulator) { 0x50 }

        before do
          bus.write(0x0200, 0x50)
          cpu.status.restore(0x00)
        end

        it 'leaves $A0 in the accumulator' do
          cpu.add_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0xA0)
        end

        it 'sets overflow and negative and clears carry', :aggregate_failures do
          cpu.add_with_carry(0x0200)
          expect(cpu.status).to be_overflow
          expect(cpu.status).to be_negative
          expect(cpu.status).not_to be_carry
        end
      end

      context 'and two negative bytes sum below $80' do
        let(:accumulator) { 0xD0 }

        before do
          bus.write(0x0200, 0x90)
          cpu.status.restore(0x00)
        end

        it 'leaves $60 in the accumulator' do
          cpu.add_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x60)
        end

        it 'sets overflow and carry', :aggregate_failures do
          cpu.add_with_carry(0x0200)
          expect(cpu.status).to be_overflow
          expect(cpu.status).to be_carry
        end
      end

      context 'and a positive and a negative byte sum past $FF' do
        let(:accumulator) { 0x50 }

        before do
          bus.write(0x0200, 0xD0)
          cpu.status.restore(0x40)
        end

        it 'leaves $20 in the accumulator' do
          cpu.add_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x20)
        end

        it 'sets carry and clears overflow', :aggregate_failures do
          cpu.add_with_carry(0x0200)
          expect(cpu.status).to be_carry
          expect(cpu.status).not_to be_overflow
        end
      end
    end

    context 'when the carry is set' do
      context 'and the sum is $30' do
        let(:accumulator) { 0x10 }

        before do
          bus.write(0x0200, 0x20)
          cpu.status.restore(0x01)
        end

        it 'leaves $31 in the accumulator' do
          cpu.add_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x31)
        end
      end

      context 'and the carry takes $FF + $00 to $100' do
        let(:accumulator) { 0xFF }

        before do
          bus.write(0x0200, 0x00)
          cpu.status.restore(0x01)
        end

        it 'leaves $00 in the accumulator' do
          cpu.add_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x00)
        end

        it 'sets carry and zero', :aggregate_failures do
          cpu.add_with_carry(0x0200)
          expect(cpu.status).to be_carry
          expect(cpu.status).to be_zero
        end
      end
    end

    context 'when decimal and interrupt disable are set' do
      context 'and the sum is $09 + $01' do
        let(:accumulator) { 0x09 }

        before do
          bus.write(0x0200, 0x01)
          cpu.status.restore(0x0C)
        end

        it 'leaves $0A in the accumulator' do
          cpu.add_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x0A)
        end

        it 'leaves decimal and interrupt disable set', :aggregate_failures do
          cpu.add_with_carry(0x0200)
          expect(cpu.status).to be_decimal
          expect(cpu.status).to be_interrupt_disable
        end
      end
    end
  end

  describe '#subtract_with_carry' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the carry is set' do
      context 'and the difference is $50 - $30' do
        let(:accumulator) { 0x50 }

        before do
          bus.write(0x0200, 0x30)
          cpu.status.restore(0xC3)
        end

        it 'leaves $20 in the accumulator' do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x20)
        end

        it 'sets carry and clears overflow, zero and negative', :aggregate_failures do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.status).to be_carry
          expect(cpu.status).not_to be_overflow
          expect(cpu.status).not_to be_zero
          expect(cpu.status).not_to be_negative
        end
      end

      context 'and the operands are equal' do
        let(:accumulator) { 0x30 }

        before do
          bus.write(0x0200, 0x30)
          cpu.status.restore(0x01)
        end

        it 'leaves $00 in the accumulator' do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x00)
        end

        it 'sets carry and zero', :aggregate_failures do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.status).to be_carry
          expect(cpu.status).to be_zero
        end
      end

      context 'and the operand is greater than the accumulator' do
        let(:accumulator) { 0x30 }

        before do
          bus.write(0x0200, 0x50)
          cpu.status.restore(0x01)
        end

        it 'leaves $E0 in the accumulator' do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0xE0)
        end

        it 'clears carry and sets negative', :aggregate_failures do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.status).not_to be_carry
          expect(cpu.status).to be_negative
        end
      end

      context 'and a positive minus a negative byte passes $7F' do
        let(:accumulator) { 0x50 }

        before do
          bus.write(0x0200, 0xB0)
          cpu.status.restore(0x01)
        end

        it 'leaves $A0 in the accumulator' do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0xA0)
        end

        it 'sets overflow and clears carry', :aggregate_failures do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.status).to be_overflow
          expect(cpu.status).not_to be_carry
        end
      end

      context 'and a negative minus a positive byte passes $80' do
        let(:accumulator) { 0xD0 }

        before do
          bus.write(0x0200, 0x70)
          cpu.status.restore(0x01)
        end

        it 'leaves $60 in the accumulator' do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x60)
        end

        it 'sets overflow and carry', :aggregate_failures do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.status).to be_overflow
          expect(cpu.status).to be_carry
        end
      end
    end

    context 'when the carry is clear' do
      context 'and the difference is $50 - $30' do
        let(:accumulator) { 0x50 }

        before do
          bus.write(0x0200, 0x30)
          cpu.status.restore(0x00)
        end

        it 'leaves $1F in the accumulator' do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x1F)
        end
      end

      context 'and the operands are equal' do
        let(:accumulator) { 0x30 }

        before do
          bus.write(0x0200, 0x30)
          cpu.status.restore(0x00)
        end

        it 'leaves $FF in the accumulator' do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0xFF)
        end

        it 'clears carry and sets negative', :aggregate_failures do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.status).not_to be_carry
          expect(cpu.status).to be_negative
        end
      end
    end

    context 'when decimal and interrupt disable are set' do
      context 'and the difference is $10 - $01' do
        let(:accumulator) { 0x10 }

        before do
          bus.write(0x0200, 0x01)
          cpu.status.restore(0x0D)
        end

        it 'leaves $0F in the accumulator' do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.accumulator).to eq(0x0F)
        end

        it 'leaves decimal and interrupt disable set', :aggregate_failures do
          cpu.subtract_with_carry(0x0200)
          expect(cpu.status).to be_decimal
          expect(cpu.status).to be_interrupt_disable
        end
      end
    end
  end
end
