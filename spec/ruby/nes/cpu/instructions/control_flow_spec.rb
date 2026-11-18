# frozen_string_literal: true

# Jumps, subroutines and BRK (https://www.nesdev.org/wiki/Instruction_reference). JSR pushes PC + 2, so "the return
# address on the stack points 1 byte before the start of the next instruction"; RTS pulls it "and then increments the
# program counter"; RTI pulls the flags, then a return address that "is the exact address of the next instruction". BRK
# pushes PC + 2 ("skips the byte after the BRK opcode"), then the flags with B set, then sets I ("set to 1 after the old
# flags are pushed") and jumps through the IRQ/BRK vector at $FFFE (https://www.nesdev.org/wiki/CPU_interrupts). Words
# go on the stack high byte first (https://www.nesdev.org/wiki/Stack). Every instruction is called as Cpu#step would:
# with the program counter past the opcode and the operand.
RSpec.describe Ruby::Nes::Cpu::Instructions::ControlFlow do
  describe '#jump' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter: 0x8003) }

    context 'when the target is $1234' do
      it 'moves the program counter to $1234' do
        cpu.jump(0x1234)
        expect(cpu.program_counter).to eq(0x1234)
      end
    end
  end

  describe '#jump_to_subroutine' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter:, stack_pointer: 0xFD) }

    let(:bus) { FlatBus.new }

    context 'when the JSR is at $8000' do
      let(:program_counter) { 0x8003 }

      it 'pushes $8002, high byte first', :aggregate_failures do
        cpu.jump_to_subroutine(0x1234)
        expect(bus.read(0x01FD)).to eq(0x80)
        expect(bus.read(0x01FC)).to eq(0x02)
      end

      it 'moves the stack pointer to $FB' do
        cpu.jump_to_subroutine(0x1234)
        expect(cpu.stack.pointer).to eq(0xFB)
      end

      it 'moves the program counter to the target' do
        cpu.jump_to_subroutine(0x1234)
        expect(cpu.program_counter).to eq(0x1234)
      end
    end

    context 'when the JSR is at $FFFD, so the program counter wrapped to $0000' do
      let(:program_counter) { 0x0000 }

      it 'pushes $FFFF', :aggregate_failures do
        cpu.jump_to_subroutine(0x1234)
        expect(bus.read(0x01FD)).to eq(0xFF)
        expect(bus.read(0x01FC)).to eq(0xFF)
      end
    end
  end

  describe '#return_from_subroutine' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, stack_pointer: 0xFB) }

    let(:bus) { FlatBus.new }

    context 'when the stack holds $8002' do
      before do
        bus.write(0x01FC, 0x02)
        bus.write(0x01FD, 0x80)
      end

      it 'moves the program counter to $8003' do
        cpu.return_from_subroutine
        expect(cpu.program_counter).to eq(0x8003)
      end

      it 'moves the stack pointer to $FD' do
        cpu.return_from_subroutine
        expect(cpu.stack.pointer).to eq(0xFD)
      end
    end

    context 'when the stack holds $FFFF' do
      before do
        bus.write(0x01FC, 0xFF)
        bus.write(0x01FD, 0xFF)
      end

      it 'wraps the program counter to $0000' do
        cpu.return_from_subroutine
        expect(cpu.program_counter).to eq(0x0000)
      end
    end
  end

  describe '#return_from_interrupt' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, stack_pointer: 0xFA) }

    let(:bus) { FlatBus.new }

    context 'when the stack holds the flags $FF and the address $1234' do
      before do
        bus.write(0x01FB, 0xFF)
        bus.write(0x01FC, 0x34)
        bus.write(0x01FD, 0x12)
      end

      it 'restores every flag but break' do
        cpu.return_from_interrupt
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0xEF)
      end

      it 'moves the program counter to $1234' do
        cpu.return_from_interrupt
        expect(cpu.program_counter).to eq(0x1234)
      end

      it 'moves the stack pointer to $FD' do
        cpu.return_from_interrupt
        expect(cpu.stack.pointer).to eq(0xFD)
      end
    end
  end

  describe '#force_interrupt' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter:, stack_pointer: 0xFD) }

    let(:bus) { FlatBus.new }

    context 'when the BRK is at $8000 and every flag is clear' do
      let(:program_counter) { 0x8001 }

      before do
        bus.write(0xFFFE, 0x34)
        bus.write(0xFFFF, 0x12)
      end

      it 'pushes $8002 and then the flags as they were, with break set', :aggregate_failures do
        cpu.force_interrupt
        expect(bus.read(0x01FD)).to eq(0x80)
        expect(bus.read(0x01FC)).to eq(0x02)
        expect(bus.read(0x01FB)).to eq(0x30)
      end

      it 'moves the stack pointer to $FA' do
        cpu.force_interrupt
        expect(cpu.stack.pointer).to eq(0xFA)
      end

      it 'sets interrupt disable' do
        cpu.force_interrupt
        expect(cpu.status).to be_interrupt_disable
      end

      it 'moves the program counter to the address at $FFFE' do
        cpu.force_interrupt
        expect(cpu.program_counter).to eq(0x1234)
      end
    end

    context 'when the BRK is at $FFFF, so the padding byte is at $0000' do
      let(:program_counter) { 0x0000 }

      it 'pushes $0001', :aggregate_failures do
        cpu.force_interrupt
        expect(bus.read(0x01FD)).to eq(0x00)
        expect(bus.read(0x01FC)).to eq(0x01)
      end
    end
  end

  describe '#no_operation' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, accumulator: 0x5A, program_counter: 0x8001) }

    context 'when the flags are $CF' do
      before { cpu.status.restore(0xCF) }

      it 'changes no register or flag', :aggregate_failures do
        cpu.no_operation
        expect(cpu.accumulator).to eq(0x5A)
        expect(cpu.program_counter).to eq(0x8001)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0xEF)
      end
    end
  end
end
