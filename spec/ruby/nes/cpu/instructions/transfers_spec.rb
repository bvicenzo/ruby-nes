# frozen_string_literal: true

# Register transfers (https://www.nesdev.org/wiki/Instruction_reference): TAX, TAY, TXA, TYA and TSX copy one register
# into another and set Z ("result == 0") and N ("result bit 7"). TXS copies X into the stack pointer and changes no
# flag: the Instruction reference gives it no flag table, and the Obelisk reference
# (https://www.nesdev.org/obelisk-6502-guide/reference.html) marks every flag "Not affected".
RSpec.describe Ruby::Nes::Cpu::Instructions::Transfers do
  describe '#transfer_accumulator_to_index_x' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, accumulator:) }

    context 'when the accumulator is $01' do
      let(:accumulator) { 0x01 }

      before { cpu.status.restore(0x82) }

      it 'copies $01 into X' do
        cpu.transfer_accumulator_to_index_x
        expect(cpu.index_x).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.transfer_accumulator_to_index_x
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the accumulator is $00' do
      let(:accumulator) { 0x00 }

      before { cpu.status.restore(0x80) }

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.transfer_accumulator_to_index_x
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the accumulator is $80' do
      let(:accumulator) { 0x80 }

      before { cpu.status.restore(0x02) }

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.transfer_accumulator_to_index_x
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:accumulator) { 0x01 }

      before { cpu.status.restore(0x4D) }

      it 'leaves them set' do
        cpu.transfer_accumulator_to_index_x
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#transfer_accumulator_to_index_y' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, accumulator:) }

    context 'when the accumulator is $01' do
      let(:accumulator) { 0x01 }

      before { cpu.status.restore(0x82) }

      it 'copies $01 into Y' do
        cpu.transfer_accumulator_to_index_y
        expect(cpu.index_y).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.transfer_accumulator_to_index_y
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the accumulator is $00' do
      let(:accumulator) { 0x00 }

      before { cpu.status.restore(0x80) }

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.transfer_accumulator_to_index_y
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the accumulator is $80' do
      let(:accumulator) { 0x80 }

      before { cpu.status.restore(0x02) }

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.transfer_accumulator_to_index_y
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:accumulator) { 0x01 }

      before { cpu.status.restore(0x4D) }

      it 'leaves them set' do
        cpu.transfer_accumulator_to_index_y
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#transfer_index_x_to_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, index_x:) }

    context 'when X is $01' do
      let(:index_x) { 0x01 }

      before { cpu.status.restore(0x82) }

      it 'copies $01 into the accumulator' do
        cpu.transfer_index_x_to_accumulator
        expect(cpu.accumulator).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.transfer_index_x_to_accumulator
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when X is $00' do
      let(:index_x) { 0x00 }

      before { cpu.status.restore(0x80) }

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.transfer_index_x_to_accumulator
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when X is $80' do
      let(:index_x) { 0x80 }

      before { cpu.status.restore(0x02) }

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.transfer_index_x_to_accumulator
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:index_x) { 0x01 }

      before { cpu.status.restore(0x4D) }

      it 'leaves them set' do
        cpu.transfer_index_x_to_accumulator
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#transfer_index_y_to_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, index_y:) }

    context 'when Y is $01' do
      let(:index_y) { 0x01 }

      before { cpu.status.restore(0x82) }

      it 'copies $01 into the accumulator' do
        cpu.transfer_index_y_to_accumulator
        expect(cpu.accumulator).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.transfer_index_y_to_accumulator
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when Y is $00' do
      let(:index_y) { 0x00 }

      before { cpu.status.restore(0x80) }

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.transfer_index_y_to_accumulator
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when Y is $80' do
      let(:index_y) { 0x80 }

      before { cpu.status.restore(0x02) }

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.transfer_index_y_to_accumulator
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:index_y) { 0x01 }

      before { cpu.status.restore(0x4D) }

      it 'leaves them set' do
        cpu.transfer_index_y_to_accumulator
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#transfer_stack_pointer_to_index_x' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, stack_pointer:) }

    context 'when the stack pointer is $01' do
      let(:stack_pointer) { 0x01 }

      before { cpu.status.restore(0x82) }

      it 'copies $01 into X' do
        cpu.transfer_stack_pointer_to_index_x
        expect(cpu.index_x).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.transfer_stack_pointer_to_index_x
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the stack pointer is $00' do
      let(:stack_pointer) { 0x00 }

      before { cpu.status.restore(0x80) }

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.transfer_stack_pointer_to_index_x
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the stack pointer is $80' do
      let(:stack_pointer) { 0x80 }

      before { cpu.status.restore(0x02) }

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.transfer_stack_pointer_to_index_x
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:stack_pointer) { 0x01 }

      before { cpu.status.restore(0x4D) }

      it 'leaves them set' do
        cpu.transfer_stack_pointer_to_index_x
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#transfer_index_x_to_stack_pointer' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, index_x:, stack_pointer: 0xFD) }

    context 'when X is $00' do
      let(:index_x) { 0x00 }

      it 'copies $00 into the stack pointer' do
        cpu.transfer_index_x_to_stack_pointer
        expect(cpu.stack.pointer).to eq(0x00)
      end

      it 'leaves the status unchanged' do
        cpu.transfer_index_x_to_stack_pointer
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end

    context 'when X is $80' do
      let(:index_x) { 0x80 }

      it 'leaves the status unchanged' do
        cpu.transfer_index_x_to_stack_pointer
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end
  end
end
