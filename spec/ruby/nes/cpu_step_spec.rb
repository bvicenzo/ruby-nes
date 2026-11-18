# frozen_string_literal: true

# One row per official opcode (https://www.nesdev.org/wiki/Instruction_reference): each runs the instruction at $8000
# and checks the cycles it took against the reference, plus one effect that only the right instruction with the right
# addressing mode produces (the operand sits only at the effective address). Indexed reads take "(5 if page crossed)"
# or "(6 if page crossed)"; stores and read-modify-write instructions list no such penalty. Branches take "2 (3 if
# branch taken, 4 if page crossed)"; each branch is tried taken and not taken with the other three flags held set, so a
# branch on the wrong flag or the wrong state fails one of the two. Opcodes outside the official 151 are unofficial
# (https://www.nesdev.org/wiki/CPU_unofficial_opcodes), left to plan 09.
#
# Before the opcode fetch, a step takes the interrupt Cpu::InterruptLines names instead (plan 07, decision 3): it pushes
# the program counter (high byte first) and the flags with B clear and bit 5 set, sets I, loads the program counter
# from the vector, NMI $FFFA or IRQ $FFFE, and takes 7 cycles (https://www.nesdev.org/wiki/CPU_interrupts). "The RTI
# instruction affects IRQ inhibition immediately", so an IRQ line still asserted when the handler returns is taken again.
RSpec.describe Ruby::Nes::Cpu do
  describe '#step' do
    let(:bus) { FlatBus.new }

    context 'when an NMI is pending' do
      subject(:cpu) do
        described_class.new(bus:, program_counter: 0x8123, stack_pointer: 0xFD).tap do |cpu|
          cpu.status.carry = true
          cpu.nmi_line = true
        end
      end

      before do
        bus.write(0x8123, 0xE8)
        bus.write_bytes(0xFFFA, [0x34, 0x12])
      end

      it 'pushes $8123 and then the flags with break clear', :aggregate_failures do
        cpu.step
        expect(bus.read(0x01FD)).to eq(0x81)
        expect(bus.read(0x01FC)).to eq(0x23)
        expect(bus.read(0x01FB)).to eq(0x21)
      end

      it 'moves the stack pointer to $FA' do
        cpu.step
        expect(cpu.stack.pointer).to eq(0xFA)
      end

      it 'sets interrupt disable' do
        cpu.step
        expect(cpu.status).to be_interrupt_disable
      end

      it 'moves the program counter to the address at $FFFA' do
        cpu.step
        expect(cpu.program_counter).to eq(0x1234)
      end

      it 'takes 7 cycles' do
        expect(cpu.step).to eq(7)
      end
    end

    context 'when the IRQ line is asserted' do
      context 'but interrupt disable is set' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000).tap do |cpu|
            cpu.status.interrupt_disable = true
            cpu.irq_line = true
          end
        end

        before do
          bus.write(0x8000, 0xE8)
          bus.write_bytes(0xFFFE, [0x34, 0x12])
        end

        it 'runs the instruction at the program counter', :aggregate_failures do
          expect(cpu.step).to eq(2)
          expect(cpu.index_x).to eq(0x01)
        end
      end

      context 'and interrupt disable is clear' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8123, stack_pointer: 0xFD).tap do |cpu|
            cpu.status.carry = true
            cpu.irq_line = true
          end
        end

        before do
          bus.write(0x8123, 0xE8)
          bus.write_bytes(0xFFFE, [0x34, 0x12])
        end

        it 'pushes $8123 and then the flags with break clear', :aggregate_failures do
          cpu.step
          expect(bus.read(0x01FD)).to eq(0x81)
          expect(bus.read(0x01FC)).to eq(0x23)
          expect(bus.read(0x01FB)).to eq(0x21)
        end

        it 'moves the stack pointer to $FA' do
          cpu.step
          expect(cpu.stack.pointer).to eq(0xFA)
        end

        it 'sets interrupt disable' do
          cpu.step
          expect(cpu.status).to be_interrupt_disable
        end

        it 'moves the program counter to the address at $FFFE' do
          cpu.step
          expect(cpu.program_counter).to eq(0x1234)
        end

        it 'takes 7 cycles' do
          expect(cpu.step).to eq(7)
        end
      end

      context 'and its handler returns with RTI while the line stays asserted' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD).tap do |cpu|
            cpu.irq_line = true
            cpu.step
            cpu.step
          end
        end

        before do
          bus.write(0x8000, 0xE8)
          bus.write_bytes(0xFFFE, [0x34, 0x12])
          bus.write(0x1234, 0x40)
        end

        it 'takes the IRQ again', :aggregate_failures do
          expect(cpu.step).to eq(7)
          expect(cpu.program_counter).to eq(0x1234)
        end
      end
    end

    context 'when the opcode is unofficial ($02)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write(0x8000, 0x02) }

      it 'raises UnknownOpcode naming the opcode and its address' do
        expect { cpu.step }.to raise_error(Ruby::Nes::Cpu::UnknownOpcode, 'unknown opcode $02 at $8000')
      end
    end

    context 'when the opcode is $00 (BRK)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD) }

      before do
        bus.write_bytes(0x8000, [0x00])
        bus.write(0xFFFE, 0x34)
        bus.write(0xFFFF, 0x12)
      end

      it 'pushes $8002 and jumps through $FFFE in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(cpu.program_counter).to eq(0x1234)
        expect(bus.read(0x01FC)).to eq(0x02)
      end
    end

    context 'when the opcode is $01 (ORA (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x01, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0xAA)
      end

      it 'leaves $EE in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $05 (ORA zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC) }

      before do
        bus.write_bytes(0x8000, [0x05, 0x10])
        bus.write(0x0010, 0xAA)
      end

      it 'leaves $EE in the accumulator in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $06 (ASL zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x06, 0x10])
        bus.write(0x0010, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $02 at $0010 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x02)
      end
    end

    context 'when the opcode is $08 (PHP)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD) }

      before { bus.write_bytes(0x8000, [0x08]) }

      it 'pushes the flags with break set in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(bus.read(0x01FD)).to eq(0x30)
      end
    end

    context 'when the opcode is $09 (ORA immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC) }

      before { bus.write_bytes(0x8000, [0x09, 0xAA]) }

      it 'leaves $EE in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $0A (ASL accumulator)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x81) }

      before do
        bus.write_bytes(0x8000, [0x0A])
        cpu.status.restore(0x01)
      end

      it 'leaves $02 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x02)
      end
    end

    context 'when the opcode is $0D (ORA absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC) }

      before do
        bus.write_bytes(0x8000, [0x0D, 0x00, 0x02])
        bus.write(0x0200, 0xAA)
      end

      it 'leaves $EE in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $0E (ASL absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x0E, 0x00, 0x02])
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $02 at $0200 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x02)
      end
    end

    context 'when the opcode is $10 (BPL) and negative is set' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x10, 0x10])
        cpu.status.restore(0xC3)
      end

      it 'moves on to the next instruction in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $10 (BPL) and negative is clear' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x10, 0x10])
        cpu.status.restore(0x43)
      end

      it 'branches to $8012 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.program_counter).to eq(0x8012)
      end
    end

    context 'when the opcode is $11 (ORA (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x11, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0xAA)
      end

      it 'leaves $EE in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $11 (ORA (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x11, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0xAA)
      end

      it 'leaves $EE in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $15 (ORA zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x15, 0x10])
        bus.write(0x0015, 0xAA)
      end

      it 'leaves $EE in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $16 (ASL zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x16, 0x10])
        bus.write(0x0015, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $02 at $0015 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x02)
      end
    end

    context 'when the opcode is $18 (CLC)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x18])
        cpu.status.restore(0xFF)
      end

      it 'clears carry in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).not_to be_carry
      end
    end

    context 'when the opcode is $19 (ORA absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x19, 0x00, 0x02])
        bus.write(0x0205, 0xAA)
      end

      it 'leaves $EE in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $19 (ORA absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x19, 0xFF, 0x02])
        bus.write(0x0300, 0xAA)
      end

      it 'leaves $EE in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $1D (ORA absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x1D, 0x00, 0x02])
        bus.write(0x0205, 0xAA)
      end

      it 'leaves $EE in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $1D (ORA absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x1D, 0xFF, 0x02])
        bus.write(0x0300, 0xAA)
      end

      it 'leaves $EE in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0xEE)
      end
    end

    context 'when the opcode is $1E (ASL absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x1E, 0x00, 0x02])
        bus.write(0x0205, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $02 at $0205 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x02)
      end
    end

    context 'when the opcode is $1E (ASL absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x1E, 0xFF, 0x02])
        bus.write(0x0300, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $02 at $0300 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x02)
      end
    end

    context 'when the opcode is $20 (JSR absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD) }

      before { bus.write_bytes(0x8000, [0x20, 0x34, 0x12]) }

      it 'pushes $8002 and jumps to $1234 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.program_counter).to eq(0x1234)
        expect(bus.read(0x01FC)).to eq(0x02)
      end
    end

    context 'when the opcode is $21 (AND (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x21, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0xAA)
      end

      it 'leaves $88 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $24 (BIT zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x00) }

      before do
        bus.write_bytes(0x8000, [0x24, 0x10])
        bus.write(0x0010, 0xC0)
      end

      it 'copies bits 7 and 6 of the byte into negative and overflow in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.status).to be_negative
        expect(cpu.status).to be_overflow
      end
    end

    context 'when the opcode is $25 (AND zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC) }

      before do
        bus.write_bytes(0x8000, [0x25, 0x10])
        bus.write(0x0010, 0xAA)
      end

      it 'leaves $88 in the accumulator in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $26 (ROL zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x26, 0x10])
        bus.write(0x0010, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0010 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x03)
      end
    end

    context 'when the opcode is $28 (PLP)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFC) }

      before do
        bus.write_bytes(0x8000, [0x28])
        bus.write(0x01FD, 0xC3)
      end

      it 'pulls the flags in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0xE3)
      end
    end

    context 'when the opcode is $29 (AND immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC) }

      before { bus.write_bytes(0x8000, [0x29, 0xAA]) }

      it 'leaves $88 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $2A (ROL accumulator)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x81) }

      before do
        bus.write_bytes(0x8000, [0x2A])
        cpu.status.restore(0x01)
      end

      it 'leaves $03 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x03)
      end
    end

    context 'when the opcode is $2C (BIT absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x00) }

      before do
        bus.write_bytes(0x8000, [0x2C, 0x00, 0x02])
        bus.write(0x0200, 0xC0)
      end

      it 'copies bits 7 and 6 of the byte into negative and overflow in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.status).to be_negative
        expect(cpu.status).to be_overflow
      end
    end

    context 'when the opcode is $2D (AND absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC) }

      before do
        bus.write_bytes(0x8000, [0x2D, 0x00, 0x02])
        bus.write(0x0200, 0xAA)
      end

      it 'leaves $88 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $2E (ROL absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x2E, 0x00, 0x02])
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0200 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x03)
      end
    end

    context 'when the opcode is $30 (BMI) and negative is clear' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x30, 0x10])
        cpu.status.restore(0x43)
      end

      it 'moves on to the next instruction in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $30 (BMI) and negative is set' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x30, 0x10])
        cpu.status.restore(0xC3)
      end

      it 'branches to $8012 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.program_counter).to eq(0x8012)
      end
    end

    context 'when the opcode is $31 (AND (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x31, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0xAA)
      end

      it 'leaves $88 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $31 (AND (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x31, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0xAA)
      end

      it 'leaves $88 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $35 (AND zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x35, 0x10])
        bus.write(0x0015, 0xAA)
      end

      it 'leaves $88 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $36 (ROL zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x36, 0x10])
        bus.write(0x0015, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0015 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x03)
      end
    end

    context 'when the opcode is $38 (SEC)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x38]) }

      it 'sets carry in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).to be_carry
      end
    end

    context 'when the opcode is $39 (AND absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x39, 0x00, 0x02])
        bus.write(0x0205, 0xAA)
      end

      it 'leaves $88 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $39 (AND absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x39, 0xFF, 0x02])
        bus.write(0x0300, 0xAA)
      end

      it 'leaves $88 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $3D (AND absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x3D, 0x00, 0x02])
        bus.write(0x0205, 0xAA)
      end

      it 'leaves $88 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $3D (AND absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x3D, 0xFF, 0x02])
        bus.write(0x0300, 0xAA)
      end

      it 'leaves $88 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x88)
      end
    end

    context 'when the opcode is $3E (ROL absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x3E, 0x00, 0x02])
        bus.write(0x0205, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0205 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x03)
      end
    end

    context 'when the opcode is $3E (ROL absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x3E, 0xFF, 0x02])
        bus.write(0x0300, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0300 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x03)
      end
    end

    context 'when the opcode is $40 (RTI)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFA) }

      before do
        bus.write_bytes(0x8000, [0x40])
        bus.write(0x01FB, 0x00)
        bus.write(0x01FC, 0x34)
        bus.write(0x01FD, 0x12)
      end

      it 'returns to the pulled address in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.program_counter).to eq(0x1234)
      end
    end

    context 'when the opcode is $41 (EOR (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x41, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0xAA)
      end

      it 'leaves $66 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $45 (EOR zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC) }

      before do
        bus.write_bytes(0x8000, [0x45, 0x10])
        bus.write(0x0010, 0xAA)
      end

      it 'leaves $66 in the accumulator in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $46 (LSR zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x46, 0x10])
        bus.write(0x0010, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $40 at $0010 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x40)
      end
    end

    context 'when the opcode is $48 (PHA)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, stack_pointer: 0xFD) }

      before { bus.write_bytes(0x8000, [0x48]) }

      it 'pushes the accumulator in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(bus.read(0x01FD)).to eq(0x42)
      end
    end

    context 'when the opcode is $49 (EOR immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC) }

      before { bus.write_bytes(0x8000, [0x49, 0xAA]) }

      it 'leaves $66 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $4A (LSR accumulator)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x81) }

      before do
        bus.write_bytes(0x8000, [0x4A])
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $4C (JMP absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x4C, 0x34, 0x12]) }

      it 'jumps to $1234 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.program_counter).to eq(0x1234)
      end
    end

    context 'when the opcode is $4D (EOR absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC) }

      before do
        bus.write_bytes(0x8000, [0x4D, 0x00, 0x02])
        bus.write(0x0200, 0xAA)
      end

      it 'leaves $66 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $4E (LSR absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x4E, 0x00, 0x02])
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $40 at $0200 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x40)
      end
    end

    context 'when the opcode is $50 (BVC) and overflow is set' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x50, 0x10])
        cpu.status.restore(0xC3)
      end

      it 'moves on to the next instruction in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $50 (BVC) and overflow is clear' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x50, 0x10])
        cpu.status.restore(0x83)
      end

      it 'branches to $8012 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.program_counter).to eq(0x8012)
      end
    end

    context 'when the opcode is $51 (EOR (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x51, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0xAA)
      end

      it 'leaves $66 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $51 (EOR (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x51, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0xAA)
      end

      it 'leaves $66 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $55 (EOR zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x55, 0x10])
        bus.write(0x0015, 0xAA)
      end

      it 'leaves $66 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $56 (LSR zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x56, 0x10])
        bus.write(0x0015, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $40 at $0015 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x40)
      end
    end

    context 'when the opcode is $58 (CLI)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x58])
        cpu.status.restore(0xFF)
      end

      it 'clears interrupt disable in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).not_to be_interrupt_disable
      end
    end

    context 'when the opcode is $59 (EOR absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x59, 0x00, 0x02])
        bus.write(0x0205, 0xAA)
      end

      it 'leaves $66 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $59 (EOR absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x59, 0xFF, 0x02])
        bus.write(0x0300, 0xAA)
      end

      it 'leaves $66 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $5D (EOR absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x5D, 0x00, 0x02])
        bus.write(0x0205, 0xAA)
      end

      it 'leaves $66 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $5D (EOR absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xCC, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x5D, 0xFF, 0x02])
        bus.write(0x0300, 0xAA)
      end

      it 'leaves $66 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x66)
      end
    end

    context 'when the opcode is $5E (LSR absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x5E, 0x00, 0x02])
        bus.write(0x0205, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $40 at $0205 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x40)
      end
    end

    context 'when the opcode is $5E (LSR absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x5E, 0xFF, 0x02])
        bus.write(0x0300, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $40 at $0300 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x40)
      end
    end

    context 'when the opcode is $60 (RTS)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFB) }

      before do
        bus.write_bytes(0x8000, [0x60])
        bus.write(0x01FC, 0x02)
        bus.write(0x01FD, 0x80)
      end

      it 'returns past the pulled address in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.program_counter).to eq(0x8003)
      end
    end

    context 'when the opcode is $61 (ADC (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x61, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x22)
      end

      it 'leaves $32 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $65 (ADC zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10) }

      before do
        bus.write_bytes(0x8000, [0x65, 0x10])
        bus.write(0x0010, 0x22)
      end

      it 'leaves $32 in the accumulator in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $66 (ROR zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x66, 0x10])
        bus.write(0x0010, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $C0 at $0010 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0xC0)
      end
    end

    context 'when the opcode is $68 (PLA)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFC) }

      before do
        bus.write_bytes(0x8000, [0x68])
        bus.write(0x01FD, 0x42)
      end

      it 'pulls $42 into the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $69 (ADC immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10) }

      before { bus.write_bytes(0x8000, [0x69, 0x22]) }

      it 'leaves $32 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $6A (ROR accumulator)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x81) }

      before do
        bus.write_bytes(0x8000, [0x6A])
        cpu.status.restore(0x01)
      end

      it 'leaves $C0 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0xC0)
      end
    end

    context 'when the opcode is $6C (JMP indirect)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x6C, 0x00, 0x02])
        bus.write(0x0200, 0x34)
        bus.write(0x0201, 0x12)
      end

      it 'jumps to the address stored at $0200 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.program_counter).to eq(0x1234)
      end
    end

    context 'when the opcode is $6D (ADC absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10) }

      before do
        bus.write_bytes(0x8000, [0x6D, 0x00, 0x02])
        bus.write(0x0200, 0x22)
      end

      it 'leaves $32 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $6E (ROR absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x6E, 0x00, 0x02])
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $C0 at $0200 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0xC0)
      end
    end

    context 'when the opcode is $70 (BVS) and overflow is clear' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x70, 0x10])
        cpu.status.restore(0x83)
      end

      it 'moves on to the next instruction in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $70 (BVS) and overflow is set' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x70, 0x10])
        cpu.status.restore(0xC3)
      end

      it 'branches to $8012 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.program_counter).to eq(0x8012)
      end
    end

    context 'when the opcode is $71 (ADC (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x71, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x22)
      end

      it 'leaves $32 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $71 (ADC (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x71, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x22)
      end

      it 'leaves $32 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $75 (ADC zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x75, 0x10])
        bus.write(0x0015, 0x22)
      end

      it 'leaves $32 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $76 (ROR zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x76, 0x10])
        bus.write(0x0015, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $C0 at $0015 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0xC0)
      end
    end

    context 'when the opcode is $78 (SEI)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x78]) }

      it 'sets interrupt disable in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).to be_interrupt_disable
      end
    end

    context 'when the opcode is $79 (ADC absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x79, 0x00, 0x02])
        bus.write(0x0205, 0x22)
      end

      it 'leaves $32 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $79 (ADC absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x79, 0xFF, 0x02])
        bus.write(0x0300, 0x22)
      end

      it 'leaves $32 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $7D (ADC absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x7D, 0x00, 0x02])
        bus.write(0x0205, 0x22)
      end

      it 'leaves $32 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $7D (ADC absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x7D, 0xFF, 0x02])
        bus.write(0x0300, 0x22)
      end

      it 'leaves $32 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x32)
      end
    end

    context 'when the opcode is $7E (ROR absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x7E, 0x00, 0x02])
        bus.write(0x0205, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $C0 at $0205 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0xC0)
      end
    end

    context 'when the opcode is $7E (ROR absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x7E, 0xFF, 0x02])
        bus.write(0x0300, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $C0 at $0300 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0xC0)
      end
    end

    context 'when the opcode is $81 (STA (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x81, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
      end

      it 'stores the accumulator at $0200 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x42)
      end
    end

    context 'when the opcode is $84 (STY zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x42) }

      before { bus.write_bytes(0x8000, [0x84, 0x10]) }

      it 'stores Y at $0010 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(bus.read(0x0010)).to eq(0x42)
      end
    end

    context 'when the opcode is $85 (STA zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42) }

      before { bus.write_bytes(0x8000, [0x85, 0x10]) }

      it 'stores the accumulator at $0010 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(bus.read(0x0010)).to eq(0x42)
      end
    end

    context 'when the opcode is $86 (STX zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x42) }

      before { bus.write_bytes(0x8000, [0x86, 0x10]) }

      it 'stores X at $0010 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(bus.read(0x0010)).to eq(0x42)
      end
    end

    context 'when the opcode is $88 (DEY)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x41) }

      before { bus.write_bytes(0x8000, [0x88]) }

      it 'changes Y to $40 in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_y).to eq(0x40)
      end
    end

    context 'when the opcode is $8A (TXA)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x42) }

      before { bus.write_bytes(0x8000, [0x8A]) }

      it 'copies $42 into the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $8C (STY absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x42) }

      before { bus.write_bytes(0x8000, [0x8C, 0x00, 0x02]) }

      it 'stores Y at $0200 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus.read(0x0200)).to eq(0x42)
      end
    end

    context 'when the opcode is $8D (STA absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42) }

      before { bus.write_bytes(0x8000, [0x8D, 0x00, 0x02]) }

      it 'stores the accumulator at $0200 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus.read(0x0200)).to eq(0x42)
      end
    end

    context 'when the opcode is $8E (STX absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x42) }

      before { bus.write_bytes(0x8000, [0x8E, 0x00, 0x02]) }

      it 'stores X at $0200 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus.read(0x0200)).to eq(0x42)
      end
    end

    context 'when the opcode is $90 (BCC) and carry is set' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x90, 0x10])
        cpu.status.restore(0xC3)
      end

      it 'moves on to the next instruction in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $90 (BCC) and carry is clear' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x90, 0x10])
        cpu.status.restore(0xC2)
      end

      it 'branches to $8012 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.program_counter).to eq(0x8012)
      end
    end

    context 'when the opcode is $91 (STA (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x91, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
      end

      it 'stores the accumulator at $0205 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0205)).to eq(0x42)
      end
    end

    context 'when the opcode is $91 (STA (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x91, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
      end

      it 'stores the accumulator at $0300 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0300)).to eq(0x42)
      end
    end

    context 'when the opcode is $94 (STY zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05, index_y: 0x42) }

      before { bus.write_bytes(0x8000, [0x94, 0x10]) }

      it 'stores Y at $0015 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus.read(0x0015)).to eq(0x42)
      end
    end

    context 'when the opcode is $95 (STA zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_x: 0x05) }

      before { bus.write_bytes(0x8000, [0x95, 0x10]) }

      it 'stores the accumulator at $0015 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus.read(0x0015)).to eq(0x42)
      end
    end

    context 'when the opcode is $96 (STX zero page,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x42, index_y: 0x05) }

      before { bus.write_bytes(0x8000, [0x96, 0x10]) }

      it 'stores X at $0015 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus.read(0x0015)).to eq(0x42)
      end
    end

    context 'when the opcode is $98 (TYA)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x42) }

      before { bus.write_bytes(0x8000, [0x98]) }

      it 'copies $42 into the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $99 (STA absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_y: 0x05) }

      before { bus.write_bytes(0x8000, [0x99, 0x00, 0x02]) }

      it 'stores the accumulator at $0205 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0205)).to eq(0x42)
      end
    end

    context 'when the opcode is $99 (STA absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_y: 0x01) }

      before { bus.write_bytes(0x8000, [0x99, 0xFF, 0x02]) }

      it 'stores the accumulator at $0300 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0300)).to eq(0x42)
      end
    end

    context 'when the opcode is $9A (TXS)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x42) }

      before { bus.write_bytes(0x8000, [0x9A]) }

      it 'copies X into the stack pointer in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.stack.pointer).to eq(0x42)
      end
    end

    context 'when the opcode is $9D (STA absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_x: 0x05) }

      before { bus.write_bytes(0x8000, [0x9D, 0x00, 0x02]) }

      it 'stores the accumulator at $0205 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0205)).to eq(0x42)
      end
    end

    context 'when the opcode is $9D (STA absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_x: 0x01) }

      before { bus.write_bytes(0x8000, [0x9D, 0xFF, 0x02]) }

      it 'stores the accumulator at $0300 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0300)).to eq(0x42)
      end
    end

    context 'when the opcode is $A0 (LDY immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xA0, 0x42]) }

      it 'loads $42 into Y in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_y).to eq(0x42)
      end
    end

    context 'when the opcode is $A1 (LDA (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0xA1, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x42)
      end

      it 'loads $42 into the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $A2 (LDX immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xA2, 0x42]) }

      it 'loads $42 into X in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_x).to eq(0x42)
      end
    end

    context 'when the opcode is $A4 (LDY zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xA4, 0x10])
        bus.write(0x0010, 0x42)
      end

      it 'loads $42 into Y in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.index_y).to eq(0x42)
      end
    end

    context 'when the opcode is $A5 (LDA zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xA5, 0x10])
        bus.write(0x0010, 0x42)
      end

      it 'loads $42 into the accumulator in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $A6 (LDX zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xA6, 0x10])
        bus.write(0x0010, 0x42)
      end

      it 'loads $42 into X in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.index_x).to eq(0x42)
      end
    end

    context 'when the opcode is $A8 (TAY)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42) }

      before { bus.write_bytes(0x8000, [0xA8]) }

      it 'copies $42 into Y in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_y).to eq(0x42)
      end
    end

    context 'when the opcode is $A9 (LDA immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xA9, 0x42]) }

      it 'loads $42 into the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $AA (TAX)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42) }

      before { bus.write_bytes(0x8000, [0xAA]) }

      it 'copies $42 into X in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_x).to eq(0x42)
      end
    end

    context 'when the opcode is $AC (LDY absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xAC, 0x00, 0x02])
        bus.write(0x0200, 0x42)
      end

      it 'loads $42 into Y in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.index_y).to eq(0x42)
      end
    end

    context 'when the opcode is $AD (LDA absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xAD, 0x00, 0x02])
        bus.write(0x0200, 0x42)
      end

      it 'loads $42 into the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $AE (LDX absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xAE, 0x00, 0x02])
        bus.write(0x0200, 0x42)
      end

      it 'loads $42 into X in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.index_x).to eq(0x42)
      end
    end

    context 'when the opcode is $B0 (BCS) and carry is clear' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xB0, 0x10])
        cpu.status.restore(0xC2)
      end

      it 'moves on to the next instruction in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $B0 (BCS) and carry is set' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xB0, 0x10])
        cpu.status.restore(0xC3)
      end

      it 'branches to $8012 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.program_counter).to eq(0x8012)
      end
    end

    context 'when the opcode is $B1 (LDA (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xB1, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x42)
      end

      it 'loads $42 into the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $B1 (LDA (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xB1, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x42)
      end

      it 'loads $42 into the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $B4 (LDY zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xB4, 0x10])
        bus.write(0x0015, 0x42)
      end

      it 'loads $42 into Y in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.index_y).to eq(0x42)
      end
    end

    context 'when the opcode is $B5 (LDA zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xB5, 0x10])
        bus.write(0x0015, 0x42)
      end

      it 'loads $42 into the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $B6 (LDX zero page,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xB6, 0x10])
        bus.write(0x0015, 0x42)
      end

      it 'loads $42 into X in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.index_x).to eq(0x42)
      end
    end

    context 'when the opcode is $B8 (CLV)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xB8])
        cpu.status.restore(0xFF)
      end

      it 'clears overflow in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).not_to be_overflow
      end
    end

    context 'when the opcode is $B9 (LDA absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xB9, 0x00, 0x02])
        bus.write(0x0205, 0x42)
      end

      it 'loads $42 into the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $B9 (LDA absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xB9, 0xFF, 0x02])
        bus.write(0x0300, 0x42)
      end

      it 'loads $42 into the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $BA (TSX)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0x42) }

      before { bus.write_bytes(0x8000, [0xBA]) }

      it 'copies the stack pointer into X in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_x).to eq(0x42)
      end
    end

    context 'when the opcode is $BC (LDY absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xBC, 0x00, 0x02])
        bus.write(0x0205, 0x42)
      end

      it 'loads $42 into Y in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.index_y).to eq(0x42)
      end
    end

    context 'when the opcode is $BC (LDY absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xBC, 0xFF, 0x02])
        bus.write(0x0300, 0x42)
      end

      it 'loads $42 into Y in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.index_y).to eq(0x42)
      end
    end

    context 'when the opcode is $BD (LDA absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xBD, 0x00, 0x02])
        bus.write(0x0205, 0x42)
      end

      it 'loads $42 into the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $BD (LDA absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xBD, 0xFF, 0x02])
        bus.write(0x0300, 0x42)
      end

      it 'loads $42 into the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x42)
      end
    end

    context 'when the opcode is $BE (LDX absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xBE, 0x00, 0x02])
        bus.write(0x0205, 0x42)
      end

      it 'loads $42 into X in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.index_x).to eq(0x42)
      end
    end

    context 'when the opcode is $BE (LDX absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xBE, 0xFF, 0x02])
        bus.write(0x0300, 0x42)
      end

      it 'loads $42 into X in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.index_x).to eq(0x42)
      end
    end

    context 'when the opcode is $C0 (CPY immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x42) }

      before { bus.write_bytes(0x8000, [0xC0, 0x42]) }

      it 'finds Y equal to the byte in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $C1 (CMP (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0xC1, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x42)
      end

      it 'finds the accumulator equal to the byte in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $C4 (CPY zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x42) }

      before do
        bus.write_bytes(0x8000, [0xC4, 0x10])
        bus.write(0x0010, 0x42)
      end

      it 'finds Y equal to the byte in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $C5 (CMP zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42) }

      before do
        bus.write_bytes(0x8000, [0xC5, 0x10])
        bus.write(0x0010, 0x42)
      end

      it 'finds the accumulator equal to the byte in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $C6 (DEC zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xC6, 0x10])
        bus.write(0x0010, 0x41)
      end

      it 'changes the byte at $0010 to $40 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x40)
      end
    end

    context 'when the opcode is $C8 (INY)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x41) }

      before { bus.write_bytes(0x8000, [0xC8]) }

      it 'changes Y to $42 in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_y).to eq(0x42)
      end
    end

    context 'when the opcode is $C9 (CMP immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42) }

      before { bus.write_bytes(0x8000, [0xC9, 0x42]) }

      it 'finds the accumulator equal to the byte in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $CA (DEX)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x41) }

      before { bus.write_bytes(0x8000, [0xCA]) }

      it 'changes X to $40 in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_x).to eq(0x40)
      end
    end

    context 'when the opcode is $CC (CPY absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x42) }

      before do
        bus.write_bytes(0x8000, [0xCC, 0x00, 0x02])
        bus.write(0x0200, 0x42)
      end

      it 'finds Y equal to the byte in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $CD (CMP absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42) }

      before do
        bus.write_bytes(0x8000, [0xCD, 0x00, 0x02])
        bus.write(0x0200, 0x42)
      end

      it 'finds the accumulator equal to the byte in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $CE (DEC absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xCE, 0x00, 0x02])
        bus.write(0x0200, 0x41)
      end

      it 'changes the byte at $0200 to $40 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x40)
      end
    end

    context 'when the opcode is $D0 (BNE) and zero is set' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xD0, 0x10])
        cpu.status.restore(0xC3)
      end

      it 'moves on to the next instruction in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $D0 (BNE) and zero is clear' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xD0, 0x10])
        cpu.status.restore(0xC1)
      end

      it 'branches to $8012 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.program_counter).to eq(0x8012)
      end
    end

    context 'when the opcode is $D1 (CMP (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xD1, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x42)
      end

      it 'finds the accumulator equal to the byte in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $D1 (CMP (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xD1, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x42)
      end

      it 'finds the accumulator equal to the byte in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $D5 (CMP zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xD5, 0x10])
        bus.write(0x0015, 0x42)
      end

      it 'finds the accumulator equal to the byte in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $D6 (DEC zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xD6, 0x10])
        bus.write(0x0015, 0x41)
      end

      it 'changes the byte at $0015 to $40 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x40)
      end
    end

    context 'when the opcode is $D8 (CLD)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xD8])
        cpu.status.restore(0xFF)
      end

      it 'clears decimal in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).not_to be_decimal
      end
    end

    context 'when the opcode is $D9 (CMP absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xD9, 0x00, 0x02])
        bus.write(0x0205, 0x42)
      end

      it 'finds the accumulator equal to the byte in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $D9 (CMP absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xD9, 0xFF, 0x02])
        bus.write(0x0300, 0x42)
      end

      it 'finds the accumulator equal to the byte in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $DD (CMP absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xDD, 0x00, 0x02])
        bus.write(0x0205, 0x42)
      end

      it 'finds the accumulator equal to the byte in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $DD (CMP absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xDD, 0xFF, 0x02])
        bus.write(0x0300, 0x42)
      end

      it 'finds the accumulator equal to the byte in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $DE (DEC absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xDE, 0x00, 0x02])
        bus.write(0x0205, 0x41)
      end

      it 'changes the byte at $0205 to $40 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x40)
      end
    end

    context 'when the opcode is $DE (DEC absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xDE, 0xFF, 0x02])
        bus.write(0x0300, 0x41)
      end

      it 'changes the byte at $0300 to $40 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x40)
      end
    end

    context 'when the opcode is $E0 (CPX immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x42) }

      before { bus.write_bytes(0x8000, [0xE0, 0x42]) }

      it 'finds X equal to the byte in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $E1 (SBC (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0xE1, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $E4 (CPX zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x42) }

      before do
        bus.write_bytes(0x8000, [0xE4, 0x10])
        bus.write(0x0010, 0x42)
      end

      it 'finds X equal to the byte in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $E5 (SBC zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50) }

      before do
        bus.write_bytes(0x8000, [0xE5, 0x10])
        bus.write(0x0010, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $E6 (INC zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xE6, 0x10])
        bus.write(0x0010, 0x41)
      end

      it 'changes the byte at $0010 to $42 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x42)
      end
    end

    context 'when the opcode is $E8 (INX)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x41) }

      before { bus.write_bytes(0x8000, [0xE8]) }

      it 'changes X to $42 in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_x).to eq(0x42)
      end
    end

    context 'when the opcode is $E9 (SBC immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50) }

      before do
        bus.write_bytes(0x8000, [0xE9, 0x10])
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $EA (NOP)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xEA]) }

      it 'moves on to the next byte in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the opcode is $EC (CPX absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x42) }

      before do
        bus.write_bytes(0x8000, [0xEC, 0x00, 0x02])
        bus.write(0x0200, 0x42)
      end

      it 'finds X equal to the byte in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.status).to be_zero
      end
    end

    context 'when the opcode is $ED (SBC absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50) }

      before do
        bus.write_bytes(0x8000, [0xED, 0x00, 0x02])
        bus.write(0x0200, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $EE (INC absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xEE, 0x00, 0x02])
        bus.write(0x0200, 0x41)
      end

      it 'changes the byte at $0200 to $42 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x42)
      end
    end

    context 'when the opcode is $F0 (BEQ) and zero is clear' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xF0, 0x10])
        cpu.status.restore(0xC1)
      end

      it 'moves on to the next instruction in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $F0 (BEQ) and zero is set' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xF0, 0x10])
        cpu.status.restore(0xC3)
      end

      it 'branches to $8012 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu.program_counter).to eq(0x8012)
      end
    end

    context 'when the opcode is $F1 (SBC (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xF1, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $F1 (SBC (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xF1, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $F5 (SBC zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xF5, 0x10])
        bus.write(0x0015, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $F6 (INC zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xF6, 0x10])
        bus.write(0x0015, 0x41)
      end

      it 'changes the byte at $0015 to $42 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x42)
      end
    end

    context 'when the opcode is $F8 (SED)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xF8]) }

      it 'sets decimal in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.status).to be_decimal
      end
    end

    context 'when the opcode is $F9 (SBC absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xF9, 0x00, 0x02])
        bus.write(0x0205, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $F9 (SBC absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xF9, 0xFF, 0x02])
        bus.write(0x0300, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $FD (SBC absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xFD, 0x00, 0x02])
        bus.write(0x0205, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $FD (SBC absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x50, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xFD, 0xFF, 0x02])
        bus.write(0x0300, 0x10)
        cpu.status.restore(0x01)
      end

      it 'leaves $40 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.accumulator).to eq(0x40)
      end
    end

    context 'when the opcode is $FE (INC absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xFE, 0x00, 0x02])
        bus.write(0x0205, 0x41)
      end

      it 'changes the byte at $0205 to $42 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x42)
      end
    end

    context 'when the opcode is $FE (INC absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xFE, 0xFF, 0x02])
        bus.write(0x0300, 0x41)
      end

      it 'changes the byte at $0300 to $42 in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x42)
      end
    end

    context 'when the opcode is $D0 (BNE), zero is clear and the target is on the next page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x80F0) }

      before { bus.write_bytes(0x80F0, [0xD0, 0x10]) }

      it 'branches to $8102 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.program_counter).to eq(0x8102)
      end
    end

    context 'when the opcode is $F0 (BEQ), zero is set and the target is on the previous page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xF0, 0xF0])
        cpu.status.restore(0x02)
      end

      it 'branches to $7FF2 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.program_counter).to eq(0x7FF2)
      end
    end

    context 'when two NOPs run one after the other' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xEA, 0xEA]) }

      it 'adds both instructions to the cycle count' do
        2.times { cpu.step }
        expect(cpu.cycles).to eq(4)
      end
    end
  end
end
