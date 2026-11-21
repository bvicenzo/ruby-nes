# frozen_string_literal: true

# The unofficial read-modify-write combos (https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes): each is
# "Equivalent to" a memory instruction "then" an accumulator instruction on the modified byte — SLO is ASL then ORA, RLA
# ROL then AND, SRE LSR then EOR, RRA ROR then ADC ("A + value / 2, where value is 9-bit"), DCP DEC then CMP and ISB
# (the wiki's ISC) INC then SBC. The modified byte goes back to memory; Z and N end up describing what the accumulator
# instruction left (A, or the comparison for DCP), not the byte written. Decimal mode is off on the 2A03, so ADC and SBC
# are binary.
RSpec.describe Ruby::Nes::Cpu::Instructions::ReadModifyWriteCombos do
  describe '#shift_left_then_or' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the byte is $81 and the accumulator $10' do
      let(:accumulator) { 0x10 }

      before do
        bus.write(0x0200, 0x81)
        allow(bus).to receive(:write).and_call_original
      end

      it 'writes the shifted byte, $02, back' do
        cpu.shift_left_then_or(0x0200)
        expect(bus.read(0x0200)).to eq(0x02)
      end

      it 'leaves their OR, $12, in the accumulator' do
        cpu.shift_left_then_or(0x0200)
        expect(cpu.accumulator).to eq(0x12)
      end

      it 'sets carry from bit 7' do
        cpu.shift_left_then_or(0x0200)
        expect(cpu.status).to be_carry
      end

      it 'writes the original byte, $81, back, then $02', :aggregate_failures do
        cpu.shift_left_then_or(0x0200)
        expect(bus).to have_received(:write).with(0x0200, 0x81).ordered
        expect(bus).to have_received(:write).with(0x0200, 0x02).ordered
        expect(bus).to have_received(:write).twice
      end
    end

    context 'when the byte shifts to $00 and the accumulator is $01' do
      let(:accumulator) { 0x01 }

      before do
        bus.write(0x0200, 0x00)
        cpu.status.restore(0x03)
      end

      it 'clears zero and carry', :aggregate_failures do
        cpu.shift_left_then_or(0x0200)
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_carry
      end
    end

    context 'when the byte shifts to $00 and the accumulator is $00' do
      let(:accumulator) { 0x00 }

      before { bus.write(0x0200, 0x80) }

      it 'sets zero' do
        cpu.shift_left_then_or(0x0200)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the byte shifts to $80' do
      let(:accumulator) { 0x00 }

      before { bus.write(0x0200, 0x40) }

      it 'sets negative' do
        cpu.shift_left_then_or(0x0200)
        expect(cpu.status).to be_negative
      end
    end
  end

  describe '#rotate_left_then_and' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the byte is $81, carry is set and the accumulator is $FF' do
      let(:accumulator) { 0xFF }

      before do
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
        allow(bus).to receive(:write).and_call_original
      end

      it 'writes the rotated byte, $03, back' do
        cpu.rotate_left_then_and(0x0200)
        expect(bus.read(0x0200)).to eq(0x03)
      end

      it 'leaves their AND, $03, in the accumulator' do
        cpu.rotate_left_then_and(0x0200)
        expect(cpu.accumulator).to eq(0x03)
      end

      it 'sets carry from bit 7' do
        cpu.rotate_left_then_and(0x0200)
        expect(cpu.status).to be_carry
      end

      it 'writes the original byte, $81, back, then $03', :aggregate_failures do
        cpu.rotate_left_then_and(0x0200)
        expect(bus).to have_received(:write).with(0x0200, 0x81).ordered
        expect(bus).to have_received(:write).with(0x0200, 0x03).ordered
        expect(bus).to have_received(:write).twice
      end
    end

    context 'when the byte rotates to $02 and the accumulator is $F0' do
      let(:accumulator) { 0xF0 }

      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x01)
      end

      it 'clears carry and sets zero', :aggregate_failures do
        cpu.rotate_left_then_and(0x0200)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).to be_zero
      end
    end

    context 'when the byte rotates to $80 and the accumulator is $80' do
      let(:accumulator) { 0x80 }

      before { bus.write(0x0200, 0x40) }

      it 'sets negative' do
        cpu.rotate_left_then_and(0x0200)
        expect(cpu.status).to be_negative
      end
    end
  end

  describe '#shift_right_then_exclusive_or' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the byte is $03 and the accumulator $10' do
      let(:accumulator) { 0x10 }

      before do
        bus.write(0x0200, 0x03)
        allow(bus).to receive(:write).and_call_original
      end

      it 'writes the shifted byte, $01, back' do
        cpu.shift_right_then_exclusive_or(0x0200)
        expect(bus.read(0x0200)).to eq(0x01)
      end

      it 'leaves their exclusive OR, $11, in the accumulator' do
        cpu.shift_right_then_exclusive_or(0x0200)
        expect(cpu.accumulator).to eq(0x11)
      end

      it 'sets carry from bit 0' do
        cpu.shift_right_then_exclusive_or(0x0200)
        expect(cpu.status).to be_carry
      end

      it 'writes the original byte, $03, back, then $01', :aggregate_failures do
        cpu.shift_right_then_exclusive_or(0x0200)
        expect(bus).to have_received(:write).with(0x0200, 0x03).ordered
        expect(bus).to have_received(:write).with(0x0200, 0x01).ordered
        expect(bus).to have_received(:write).twice
      end
    end

    context 'when the byte shifts to $01 and the accumulator is $01' do
      let(:accumulator) { 0x01 }

      before do
        bus.write(0x0200, 0x02)
        cpu.status.restore(0x01)
      end

      it 'clears carry and sets zero', :aggregate_failures do
        cpu.shift_right_then_exclusive_or(0x0200)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).to be_zero
      end
    end

    context 'when the byte shifts to $00 and the accumulator is $80' do
      let(:accumulator) { 0x80 }

      before { bus.write(0x0200, 0x00) }

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.shift_right_then_exclusive_or(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end
  end

  describe '#rotate_right_then_add' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the byte is $03, carry is clear and the accumulator is $10' do
      let(:accumulator) { 0x10 }

      before do
        bus.write(0x0200, 0x03)
        allow(bus).to receive(:write).and_call_original
      end

      it 'writes the rotated byte, $01, back' do
        cpu.rotate_right_then_add(0x0200)
        expect(bus.read(0x0200)).to eq(0x01)
      end

      it 'adds the rotated byte and the bit rotated out, leaving $12' do
        cpu.rotate_right_then_add(0x0200)
        expect(cpu.accumulator).to eq(0x12)
      end

      it 'clears carry, overflow, zero and negative' do
        cpu.rotate_right_then_add(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end

      it 'writes the original byte, $03, back, then $01', :aggregate_failures do
        cpu.rotate_right_then_add(0x0200)
        expect(bus).to have_received(:write).with(0x0200, 0x03).ordered
        expect(bus).to have_received(:write).with(0x0200, 0x01).ordered
        expect(bus).to have_received(:write).twice
      end
    end

    context 'when the byte is $02, carry is set and the accumulator is $00' do
      let(:accumulator) { 0x00 }

      before do
        bus.write(0x0200, 0x02)
        cpu.status.restore(0x01)
      end

      it 'writes the byte with the old carry in bit 7, $81, back' do
        cpu.rotate_right_then_add(0x0200)
        expect(bus.read(0x0200)).to eq(0x81)
      end

      it 'leaves $81 in the accumulator and sets negative', :aggregate_failures do
        cpu.rotate_right_then_add(0x0200)
        expect(cpu.accumulator).to eq(0x81)
        expect(cpu.status).to be_negative
      end
    end

    context 'when the sum overflows into the sign bit ($7F + $01)' do
      let(:accumulator) { 0x7F }

      before { bus.write(0x0200, 0x02) }

      it 'sets overflow' do
        cpu.rotate_right_then_add(0x0200)
        expect(cpu.status).to be_overflow
      end
    end

    context 'when the sum carries out of bit 7 ($FF + $01)' do
      let(:accumulator) { 0xFF }

      before { bus.write(0x0200, 0x02) }

      it 'leaves $00, setting carry and zero', :aggregate_failures do
        cpu.rotate_right_then_add(0x0200)
        expect(cpu.accumulator).to eq(0x00)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_zero
      end
    end
  end

  describe '#decrement_then_compare' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator: 0x20) }

    let(:bus) { FlatBus.new }

    context 'when the decremented byte is below the accumulator ($11 - 1 < $20)' do
      before do
        bus.write(0x0200, 0x11)
        cpu.status.restore(0x82)
        allow(bus).to receive(:write).and_call_original
      end

      it 'writes the decremented byte, $10, back' do
        cpu.decrement_then_compare(0x0200)
        expect(bus.read(0x0200)).to eq(0x10)
      end

      it 'leaves the accumulator unchanged' do
        cpu.decrement_then_compare(0x0200)
        expect(cpu.accumulator).to eq(0x20)
      end

      it 'sets carry and clears zero and negative', :aggregate_failures do
        cpu.decrement_then_compare(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end

      it 'writes the original byte, $11, back, then $10', :aggregate_failures do
        cpu.decrement_then_compare(0x0200)
        expect(bus).to have_received(:write).with(0x0200, 0x11).ordered
        expect(bus).to have_received(:write).with(0x0200, 0x10).ordered
        expect(bus).to have_received(:write).twice
      end
    end

    context 'when the decremented byte equals the accumulator ($21 - 1)' do
      before { bus.write(0x0200, 0x21) }

      it 'sets carry and zero', :aggregate_failures do
        cpu.decrement_then_compare(0x0200)
        expect(cpu.status).to be_carry
        expect(cpu.status).to be_zero
      end
    end

    context 'when the decremented byte is above the accumulator ($22 - 1 > $20)' do
      before do
        bus.write(0x0200, 0x22)
        cpu.status.restore(0x01)
      end

      it 'clears carry and sets negative from the difference, $FF', :aggregate_failures do
        cpu.decrement_then_compare(0x0200)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).to be_negative
      end
    end

    context 'when the byte is $00' do
      before { bus.write(0x0200, 0x00) }

      it 'writes $FF back' do
        cpu.decrement_then_compare(0x0200)
        expect(bus.read(0x0200)).to eq(0xFF)
      end
    end
  end

  describe '#increment_then_subtract' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:) }

    let(:bus) { FlatBus.new }

    context 'when the byte is $0F, carry is set and the accumulator is $20' do
      let(:accumulator) { 0x20 }

      before do
        bus.write(0x0200, 0x0F)
        cpu.status.restore(0x01)
        allow(bus).to receive(:write).and_call_original
      end

      it 'writes the incremented byte, $10, back' do
        cpu.increment_then_subtract(0x0200)
        expect(bus.read(0x0200)).to eq(0x10)
      end

      it 'subtracts it, leaving $10 with carry set (no borrow)', :aggregate_failures do
        cpu.increment_then_subtract(0x0200)
        expect(cpu.accumulator).to eq(0x10)
        expect(cpu.status).to be_carry
      end

      it 'writes the original byte, $0F, back, then $10', :aggregate_failures do
        cpu.increment_then_subtract(0x0200)
        expect(bus).to have_received(:write).with(0x0200, 0x0F).ordered
        expect(bus).to have_received(:write).with(0x0200, 0x10).ordered
        expect(bus).to have_received(:write).twice
      end
    end

    context 'when the byte is $0F, carry is clear and the accumulator is $20' do
      let(:accumulator) { 0x20 }

      before { bus.write(0x0200, 0x0F) }

      it 'subtracts one more, leaving $0F' do
        cpu.increment_then_subtract(0x0200)
        expect(cpu.accumulator).to eq(0x0F)
      end
    end

    context 'when the incremented byte is above the accumulator ($1F + 1 > $10)' do
      let(:accumulator) { 0x10 }

      before do
        bus.write(0x0200, 0x1F)
        cpu.status.restore(0x01)
      end

      it 'borrows: leaves $F0, clears carry and sets negative', :aggregate_failures do
        cpu.increment_then_subtract(0x0200)
        expect(cpu.accumulator).to eq(0xF0)
        expect(cpu.status).not_to be_carry
        expect(cpu.status).to be_negative
      end
    end

    context 'when the difference overflows the sign ($80 - $01)' do
      let(:accumulator) { 0x80 }

      before do
        bus.write(0x0200, 0x00)
        cpu.status.restore(0x01)
      end

      it 'sets overflow' do
        cpu.increment_then_subtract(0x0200)
        expect(cpu.status).to be_overflow
      end
    end

    context 'when the byte is $FF' do
      let(:accumulator) { 0x00 }

      before do
        bus.write(0x0200, 0xFF)
        cpu.status.restore(0x01)
      end

      it 'writes $00 back and subtracts it, setting zero', :aggregate_failures do
        cpu.increment_then_subtract(0x0200)
        expect(bus.read(0x0200)).to eq(0x00)
        expect(cpu.status).to be_zero
      end
    end
  end
end
