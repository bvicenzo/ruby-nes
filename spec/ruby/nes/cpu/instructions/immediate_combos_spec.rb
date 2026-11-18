# frozen_string_literal: true

# The unofficial immediate combos (https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes). ANC "Does AND #i,
# setting N and Z flags based on the result. Then it copies N (bit 7) to C." ALR is "Equivalent to AND #i then LSR A."
# ARR is "Similar to AND #i then ROR A, except sets the flags differently. N and Z are normal, but C is bit 6 and V is
# bit 6 xor bit 5." AXS "Sets X to {(A AND X) - #value without borrow}, and updates NZC" (C as CMP sets it), and "it
# does not affect the V flag" (https://www.nesdev.org/6502_cpu.txt). Each is given the operand's address, as the
# immediate addressing mode resolves it.
RSpec.describe Ruby::Nes::Cpu::Instructions::ImmediateCombos do
  describe '#and_then_copy_sign_to_carry' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the AND is $80' do
      let(:accumulator) { 0xF0 }

      before { bus.write(0x0200, 0x80) }

      it 'leaves $80 in the accumulator' do
        cpu.and_then_copy_sign_to_carry(0x0200)
        expect(cpu.accumulator).to eq(0x80)
      end

      it 'sets negative and carry', :aggregate_failures do
        cpu.and_then_copy_sign_to_carry(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).to be_carry
      end
    end

    context 'when the AND is $01' do
      let(:accumulator) { 0x0F }

      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x83)
      end

      it 'clears negative, carry and zero', :aggregate_failures do
        cpu.and_then_copy_sign_to_carry(0x0200)
        expect(cpu.status).not_to be_negative
        expect(cpu.status).not_to be_carry
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when the AND is $00' do
      let(:accumulator) { 0xF0 }

      before { bus.write(0x0200, 0x0F) }

      it 'sets zero' do
        cpu.and_then_copy_sign_to_carry(0x0200)
        expect(cpu.status).to be_zero
      end
    end
  end

  describe '#and_then_shift_right' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator: 0xFF) }

    let(:bus) { FlatBus.new }

    context 'when the AND is $03' do
      before { bus.write(0x0200, 0x03) }

      it 'leaves it shifted right, $01, in the accumulator' do
        cpu.and_then_shift_right(0x0200)
        expect(cpu.accumulator).to eq(0x01)
      end

      it 'sets carry from bit 0' do
        cpu.and_then_shift_right(0x0200)
        expect(cpu.status).to be_carry
      end
    end

    context 'when the AND is $02' do
      before do
        bus.write(0x0200, 0x02)
        cpu.status.restore(0x01)
      end

      it 'clears carry' do
        cpu.and_then_shift_right(0x0200)
        expect(cpu.status).not_to be_carry
      end
    end

    context 'when the AND is $01' do
      before { bus.write(0x0200, 0x01) }

      it 'sets zero' do
        cpu.and_then_shift_right(0x0200)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the AND is $80' do
      before do
        bus.write(0x0200, 0x80)
        cpu.status.restore(0x80)
      end

      it 'clears negative' do
        cpu.and_then_shift_right(0x0200)
        expect(cpu.status).not_to be_negative
      end
    end
  end

  describe '#and_then_rotate_right' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator: 0xFF) }

    let(:bus) { FlatBus.new }

    context 'when the AND is $FF and carry is set' do
      before do
        bus.write(0x0200, 0xFF)
        cpu.status.restore(0x41)
      end

      it 'leaves it rotated right with the carry in bit 7, $FF' do
        cpu.and_then_rotate_right(0x0200)
        expect(cpu.accumulator).to eq(0xFF)
      end

      it 'sets carry and negative and clears overflow (bits 6 and 5 both set)', :aggregate_failures do
        cpu.and_then_rotate_right(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_overflow
      end
    end

    context 'when the AND is $80 and carry is clear' do
      before { bus.write(0x0200, 0x80) }

      it 'leaves $40, setting carry and overflow (bit 6 set, bit 5 clear)', :aggregate_failures do
        cpu.and_then_rotate_right(0x0200)
        expect(cpu.accumulator).to eq(0x40)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_overflow
      end
    end

    context 'when the AND is $40 and carry is clear' do
      before { bus.write(0x0200, 0x40) }

      it 'leaves $20, clearing carry and setting overflow (bit 6 clear, bit 5 set)', :aggregate_failures do
        cpu.and_then_rotate_right(0x0200)
        expect(cpu.accumulator).to eq(0x20)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).to be_overflow
      end
    end

    context 'when the AND is $01 and carry is clear' do
      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x40)
      end

      it 'leaves $00, clearing carry and overflow and setting zero', :aggregate_failures do
        cpu.and_then_rotate_right(0x0200)
        expect(cpu.accumulator).to eq(0x00)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).not_to be_overflow
        expect(cpu.status).to be_zero
      end
    end
  end

  describe '#and_index_x_then_subtract' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:, index_x:) }

    let(:bus) { FlatBus.new }

    context 'when the AND, $30, is above the operand ($10) and carry is clear' do
      let(:accumulator) { 0xF0 }
      let(:index_x) { 0x3C }

      before { bus.write(0x0200, 0x10) }

      it 'leaves the difference without borrow, $20, in index X' do
        cpu.and_index_x_then_subtract(0x0200)
        expect(cpu.index_x).to eq(0x20)
      end

      it 'leaves the accumulator unchanged' do
        cpu.and_index_x_then_subtract(0x0200)
        expect(cpu.accumulator).to eq(0xF0)
      end

      it 'sets carry and clears zero and negative', :aggregate_failures do
        cpu.and_index_x_then_subtract(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the AND equals the operand ($30)' do
      let(:accumulator) { 0xF0 }
      let(:index_x) { 0x3C }

      before { bus.write(0x0200, 0x30) }

      it 'leaves $00, setting carry and zero', :aggregate_failures do
        cpu.and_index_x_then_subtract(0x0200)
        expect(cpu.index_x).to eq(0x00)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_zero
      end
    end

    context 'when the AND is below the operand ($31)' do
      let(:accumulator) { 0xF0 }
      let(:index_x) { 0x3C }

      before do
        bus.write(0x0200, 0x31)
        cpu.status.restore(0x01)
      end

      it 'leaves $FF, clearing carry and setting negative', :aggregate_failures do
        cpu.and_index_x_then_subtract(0x0200)
        expect(cpu.index_x).to eq(0xFF)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).to be_negative
      end
    end

    context 'when overflow is set and the difference crosses the sign ($80 - $01)' do
      let(:accumulator) { 0x80 }
      let(:index_x) { 0x80 }

      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x40)
      end

      it 'leaves overflow set' do
        cpu.and_index_x_then_subtract(0x0200)
        expect(cpu.status).to be_overflow
      end
    end
  end
end
