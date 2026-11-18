# frozen_string_literal: true

# The seven unstable unofficial opcodes, after "No More Secrets" (NMOS 6510 Unintended Opcodes, V0.95,
# https://csdb.dk/release/?id=198357), approximate by nature (plan 09, decision 1):
#
# - ANE (the wiki's XAA): "A = (A | {CONST}) & X & #{imm}"; LAX #imm: "A,X = (A | {CONST}) & #{imm}". CONST is "chip-
#   and/or temperature dependent"; the document advises emulators to use $EF for ANE ("$EF in regular cycles") and
#   "$EE for the 'magic constant'" for LAX #imm. Z and N follow the result ("N and Z flags are set according to the
#   result of XAA", https://www.nesdev.org/wiki/Visual6502wiki/6502_Opcode_8B_(XAA,_ANE)).
# - SHA (the wiki's AHX) "{addr} = A & X & {H+1}", SHX "{addr} = X & {H+1}", SHY "{addr} = Y & {H+1}", TAS "SP = A & X,
#   {addr} = A & X & {H+1}": H is "the high byte of the target address of the argument", before the index is added.
#   When the index crosses a page, "the highbyte of the target address is incremented by one (as expected), and then
#   ANDed with" the value, so the byte lands on the page the value names. "None of these opcodes affect the
#   accumulator, the X register, the Y register, or the processor status register" (TAS sets SP).
# - LAS: "A,X,SP = {addr} & SP"; "N and Z are set as expected by a load instruction".
#
# Each method is given the effective address its addressing mode resolved; the stores find H from it and the index.
RSpec.describe Ruby::Nes::Cpu::Instructions::Unstable do
  describe '#and_index_x_and_operand' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:, index_x:) }

    let(:bus) { FlatBus.new }

    context 'when the accumulator is $FF' do
      let(:accumulator) { 0xFF }
      let(:index_x) { 0xF0 }

      before { bus.write(0x0200, 0x3C) }

      it 'leaves index X AND the operand, $30, in the accumulator' do
        cpu.and_index_x_and_operand(0x0200)
        expect(cpu.accumulator).to eq(0x30)
      end

      it 'leaves index X unchanged' do
        cpu.and_index_x_and_operand(0x0200)
        expect(cpu.index_x).to eq(0xF0)
      end
    end

    context 'when the accumulator is $00' do
      let(:accumulator) { 0x00 }
      let(:index_x) { 0xFF }

      before { bus.write(0x0200, 0xFF) }

      it 'leaves the magic constant, $EF, in the accumulator and sets negative', :aggregate_failures do
        cpu.and_index_x_and_operand(0x0200)
        expect(cpu.accumulator).to eq(0xEF)
        expect(cpu.status).to be_negative
      end
    end

    context 'when the operand is $00' do
      let(:accumulator) { 0xFF }
      let(:index_x) { 0xFF }

      before { bus.write(0x0200, 0x00) }

      it 'leaves $00, setting zero', :aggregate_failures do
        cpu.and_index_x_and_operand(0x0200)
        expect(cpu.accumulator).to eq(0x00)
        expect(cpu.status).to be_zero
      end
    end
  end

  describe '#and_operand_into_accumulator_and_index_x' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:, index_x: 0x5A) }

    let(:bus) { FlatBus.new }

    context 'when the accumulator is $FF' do
      let(:accumulator) { 0xFF }

      before { bus.write(0x0200, 0x81) }

      it 'loads the operand, $81, into the accumulator and index X and sets negative', :aggregate_failures do
        cpu.and_operand_into_accumulator_and_index_x(0x0200)
        expect(cpu).to have_attributes(accumulator: 0x81, index_x: 0x81)
        expect(cpu.status).to be_negative
      end
    end

    context 'when the accumulator is $00' do
      let(:accumulator) { 0x00 }

      before { bus.write(0x0200, 0xFF) }

      it 'loads the magic constant, $EE, into the accumulator and index X' do
        cpu.and_operand_into_accumulator_and_index_x(0x0200)
        expect(cpu).to have_attributes(accumulator: 0xEE, index_x: 0xEE)
      end
    end

    context 'when the operand is $00' do
      let(:accumulator) { 0xFF }

      before { bus.write(0x0200, 0x00) }

      it 'loads $00, setting zero', :aggregate_failures do
        cpu.and_operand_into_accumulator_and_index_x(0x0200)
        expect(cpu).to have_attributes(accumulator: 0x00, index_x: 0x00)
        expect(cpu.status).to be_zero
      end
    end
  end

  describe '#store_accumulator_and_index_x_and_high_byte' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator: 0xF1, index_x: 0xFF, index_y:) }

    let(:bus) { FlatBus.new }

    context 'when the index stays on the base page ($12F0 + $05)' do
      let(:index_y) { 0x05 }

      it 'writes A AND X AND the base high byte plus one, $11, at $12F5' do
        cpu.store_accumulator_and_index_x_and_high_byte(0x12F5)
        expect(bus.read(0x12F5)).to eq(0x11)
      end

      it 'leaves the registers and the status unchanged', :aggregate_failures do
        cpu.store_accumulator_and_index_x_and_high_byte(0x12F5)
        expect(cpu).to have_attributes(accumulator: 0xF1, index_x: 0xFF, index_y: 0x05)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end

    context 'when the index crosses into the next page ($12F0 + $20)' do
      let(:index_y) { 0x20 }

      it 'writes $11 on the page the value names, at $1110', :aggregate_failures do
        cpu.store_accumulator_and_index_x_and_high_byte(0x1310)
        expect(bus.read(0x1110)).to eq(0x11)
        expect(bus.read(0x1310)).to eq(0x00)
      end
    end
  end

  describe '#store_index_x_and_high_byte' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, index_x: 0xF1, index_y:) }

    let(:bus) { FlatBus.new }

    context 'when the index stays on the base page ($12F0 + $05)' do
      let(:index_y) { 0x05 }

      it 'writes X AND the base high byte plus one, $11, at $12F5' do
        cpu.store_index_x_and_high_byte(0x12F5)
        expect(bus.read(0x12F5)).to eq(0x11)
      end
    end

    context 'when the index crosses into the next page ($12F0 + $20)' do
      let(:index_y) { 0x20 }

      it 'writes $11 on the page the value names, at $1110', :aggregate_failures do
        cpu.store_index_x_and_high_byte(0x1310)
        expect(bus.read(0x1110)).to eq(0x11)
        expect(bus.read(0x1310)).to eq(0x00)
      end
    end

    context 'when the base high byte is $FF ($FFF0 + $05)' do
      let(:index_y) { 0x05 }

      before { bus.write(0xFFF5, 0x77) }

      it 'writes X AND $00, $00' do
        cpu.store_index_x_and_high_byte(0xFFF5)
        expect(bus.read(0xFFF5)).to eq(0x00)
      end
    end
  end

  describe '#store_index_y_and_high_byte' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, index_x:, index_y: 0xF1) }

    let(:bus) { FlatBus.new }

    context 'when the index stays on the base page ($12F0 + $05)' do
      let(:index_x) { 0x05 }

      it 'writes Y AND the base high byte plus one, $11, at $12F5' do
        cpu.store_index_y_and_high_byte(0x12F5)
        expect(bus.read(0x12F5)).to eq(0x11)
      end
    end

    context 'when the index crosses into the next page ($12F0 + $20)' do
      let(:index_x) { 0x20 }

      it 'writes $11 on the page the value names, at $1110', :aggregate_failures do
        cpu.store_index_y_and_high_byte(0x1310)
        expect(bus.read(0x1110)).to eq(0x11)
        expect(bus.read(0x1310)).to eq(0x00)
      end
    end
  end

  describe '#transfer_and_store_stack_pointer' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator: 0xF0, index_x: 0x3F, index_y:, stack_pointer: 0xFD) }

    let(:bus) { FlatBus.new }

    context 'when the index stays on the base page ($12F0 + $05)' do
      let(:index_y) { 0x05 }

      it 'moves A AND X, $30, into the stack pointer' do
        cpu.transfer_and_store_stack_pointer(0x12F5)
        expect(cpu.stack.pointer).to eq(0x30)
      end

      it 'writes it AND the base high byte plus one, $10, at $12F5' do
        cpu.transfer_and_store_stack_pointer(0x12F5)
        expect(bus.read(0x12F5)).to eq(0x10)
      end

      it 'leaves the accumulator, index X and the status unchanged', :aggregate_failures do
        cpu.transfer_and_store_stack_pointer(0x12F5)
        expect(cpu).to have_attributes(accumulator: 0xF0, index_x: 0x3F)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end

    context 'when the index crosses into the next page ($12F0 + $20)' do
      let(:index_y) { 0x20 }

      it 'writes $10 on the page the value names, at $1010', :aggregate_failures do
        cpu.transfer_and_store_stack_pointer(0x1310)
        expect(bus.read(0x1010)).to eq(0x10)
        expect(bus.read(0x1310)).to eq(0x00)
      end
    end
  end

  describe '#load_accumulator_index_x_and_stack_pointer' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, stack_pointer:) }

    let(:bus) { FlatBus.new }

    context 'when the byte is $F3 and the stack pointer $3C' do
      let(:stack_pointer) { 0x3C }

      before do
        bus.write(0x0200, 0xF3)
        cpu.status.restore(0x82)
      end

      it 'loads their AND, $30, into the accumulator, index X and the stack pointer', :aggregate_failures do
        cpu.load_accumulator_index_x_and_stack_pointer(0x0200)
        expect(cpu).to have_attributes(accumulator: 0x30, index_x: 0x30)
        expect(cpu.stack.pointer).to eq(0x30)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.load_accumulator_index_x_and_stack_pointer(0x0200)
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when their AND is $00' do
      let(:stack_pointer) { 0x0F }

      before { bus.write(0x0200, 0xF0) }

      it 'sets zero' do
        cpu.load_accumulator_index_x_and_stack_pointer(0x0200)
        expect(cpu.status).to be_zero
      end
    end

    context 'when their AND is $80' do
      let(:stack_pointer) { 0xFD }

      before { bus.write(0x0200, 0x80) }

      it 'sets negative' do
        cpu.load_accumulator_index_x_and_stack_pointer(0x0200)
        expect(cpu.status).to be_negative
      end
    end
  end
end
