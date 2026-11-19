# frozen_string_literal: true

# Reset (https://www.nesdev.org/wiki/CPU_interrupts) "goes through the same sequence [as NMI and IRQ, seven ticks], but
# suppresses writes, decrementing the stack pointer thrice without modifying memory", sets I and loads the program
# counter from the reset vector at $FFFC. At power (https://www.nesdev.org/wiki/CPU_power_up_state) A, X and Y are 0,
# S is "$00 - 3 = $FD", I is set and C, Z, D, V and N are clear; after a reset A, X, Y and the other flags are
# "unchanged". The status is observed through the byte an interrupt would push (bit 5 set, B clear).
RSpec.describe Ruby::Nes::Cpu::Interrupts do
  describe '#reset' do
    context 'when the CPU was just built' do
      subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

      let(:bus) { FlatBus.new }

      before { bus.write_bytes(0xFFFC, [0x34, 0x12]) }

      it 'leaves A, X and Y at zero', :aggregate_failures do
        cpu.reset
        expect(cpu.accumulator).to eq(0x00)
        expect(cpu.index_x).to eq(0x00)
        expect(cpu.index_y).to eq(0x00)
      end

      it 'moves the stack pointer to $FD' do
        cpu.reset
        expect(cpu.stack.pointer).to eq(0xFD)
      end

      it 'leaves every flag clear but interrupt disable' do
        cpu.reset
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x24)
      end

      it 'loads the program counter from the reset vector' do
        cpu.reset
        expect(cpu.program_counter).to eq(0x1234)
      end

      it 'counts 7 cycles' do
        cpu.reset
        expect(cpu.cycles).to eq(7)
      end

      it 'returns 7' do
        expect(cpu.reset).to eq(7)
      end
    end

    context 'when the CPU was running with registers and flags set' do
      context 'and the stack pointer is $FD' do
        subject(:cpu) do
          Ruby::Nes::Cpu.new(
            bus:,
            accumulator: 0x11,
            index_x: 0x22,
            index_y: 0x33,
            program_counter: 0x8000,
            stack_pointer: 0xFD
          )
        end

        let(:bus) { FlatBus.new }

        before do
          bus.write_bytes(0x01FB, [0xAA, 0xBB, 0xCC])
          bus.write(0x8000, 0xEA)
          bus.write_bytes(0xFFFC, [0x34, 0x12])
          cpu.status.restore(0xCB)
          cpu.step
        end

        it 'moves the stack pointer to $FA' do
          cpu.reset
          expect(cpu.stack.pointer).to eq(0xFA)
        end

        it 'writes nothing to the stack page' do
          cpu.reset
          expect([bus.read(0x01FB), bus.read(0x01FC), bus.read(0x01FD)]).to eq([0xAA, 0xBB, 0xCC])
        end

        it 'sets interrupt disable' do
          cpu.reset
          expect(cpu.status).to be_interrupt_disable
        end

        it 'keeps A, X and Y', :aggregate_failures do
          cpu.reset
          expect(cpu.accumulator).to eq(0x11)
          expect(cpu.index_x).to eq(0x22)
          expect(cpu.index_y).to eq(0x33)
        end

        it 'keeps carry, zero, decimal, overflow and negative', :aggregate_failures do
          cpu.reset
          expect(cpu.status).to be_carry
          expect(cpu.status).to be_zero
          expect(cpu.status).to be_decimal
          expect(cpu.status).to be_overflow
          expect(cpu.status).to be_negative
        end

        it 'loads the program counter from the reset vector' do
          cpu.reset
          expect(cpu.program_counter).to eq(0x1234)
        end

        it 'adds 7 cycles to those already counted' do
          cpu.reset
          expect(cpu.cycles).to eq(9)
        end

        it 'returns 7' do
          expect(cpu.reset).to eq(7)
        end
      end

      context 'and the stack pointer is $01' do
        subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, stack_pointer: 0x01) }

        it 'wraps the stack pointer to $FE' do
          cpu.reset
          expect(cpu.stack.pointer).to eq(0xFE)
        end
      end
    end

    context 'when an NMI is pending' do
      subject(:cpu) { Ruby::Nes::Cpu.new(bus:).tap { |cpu| cpu.nmi_line_changed(true, 0) } }

      let(:bus) { FlatBus.new }

      before do
        bus.write_bytes(0xFFFC, [0x34, 0x12])
        bus.write(0x1234, 0xEA)
      end

      it 'discards it: the next step runs the instruction at the reset vector', :aggregate_failures do
        cpu.reset
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x1235)
      end
    end

    # The jam opcodes "halt the CPU until reset" (https://www.nesdev.org/wiki/CPU_unofficial_opcodes).
    context 'when the CPU is jammed' do
      subject(:cpu) { Ruby::Nes::Cpu.new(bus:).tap(&:jam) }

      let(:bus) { FlatBus.new }

      before do
        bus.write_bytes(0xFFFC, [0x34, 0x12])
        bus.write(0x1234, 0xEA)
      end

      it 'releases it: the next step runs the instruction at the reset vector', :aggregate_failures do
        cpu.reset
        expect(cpu).not_to be_jammed
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x1235)
      end
    end
  end

  describe '#pending_interrupt' do
    context 'when no interrupt is due' do
      subject(:cpu) { Ruby::Nes::Cpu.new(bus:, cycles: 10) }

      let(:bus) { FlatBus.new }

      it 'returns nothing' do
        expect(cpu.pending_interrupt).to be_nil
      end
    end

    context 'when an NMI is due' do
      subject(:cpu) { Ruby::Nes::Cpu.new(bus:, cycles: 10).tap { |cpu| cpu.nmi_line_changed(true, 8) } }

      let(:bus) { FlatBus.new }

      before { bus.write_bytes(0xFFFA, [0x34, 0x12]) }

      it 'returns the NMI vector' do
        expect(cpu.pending_interrupt).to eq(0xFFFA)
      end

      it 'leaves it to the next step' do
        cpu.pending_interrupt
        cpu.step
        expect(cpu.program_counter).to eq(0x1234)
      end
    end
  end
end
