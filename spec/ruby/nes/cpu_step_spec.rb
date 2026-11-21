# frozen_string_literal: true

# One row per opcode, official (https://www.nesdev.org/wiki/Instruction_reference) or not: each runs the instruction
# at $8000 and checks the cycles it took against the reference, plus one effect that only the right instruction with the
# right addressing mode produces (the operand sits only at the effective address). Indexed reads take "(5 if page
# crossed)" or "(6 if page crossed)"; stores and read-modify-write instructions list no such penalty. Branches take "2
# (3 if branch taken, 4 if page crossed)"; each branch is tried taken and not taken with the other three flags held set,
# so a branch on the wrong flag or the wrong state fails one of the two. The 105 unofficial opcodes
# (https://www.nesdev.org/wiki/CPU_unofficial_opcodes) follow the same pattern, with the cycles of
# https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes: the read-modify-write combos "always have a page
# crossing penalty even if not crossing a page" (fixed counts), LAX, LAS and the absolute,X NOPs read like LDA, and the
# unstable stores write their value ANDed with the base address's high byte plus one ("No More Secrets",
# https://csdb.dk/release/?id=198357). A JAM opcode halts the CPU "until reset" (plan 09, decision 2).
#
# Before the opcode fetch, a step takes the interrupt Cpu::InterruptLines names instead (plan 07, decision 3): it pushes
# the program counter (high byte first) and the flags with B clear and bit 5 set, sets I, loads the program counter
# from the vector, NMI $FFFA or IRQ $FFFE, and takes 7 cycles (https://www.nesdev.org/wiki/CPU_interrupts). "The RTI
# instruction affects IRQ inhibition immediately", so an IRQ line still asserted when the handler returns is taken
# again.
RSpec.describe Ruby::Nes::Cpu do
  describe '#step' do
    let(:bus) { FlatBus.new }

    # A jammed CPU (a JAM opcode ran) is halted "until reset" (https://www.nesdev.org/wiki/CPU_unofficial_opcodes). No
    # reference gives what a step costs then, nor whether NMI and IRQ act on it: by convention (plan 09, decision 2) it
    # touches no bus, takes no interrupt and takes 2 cycles, so the console keeps running the PPU and APU.
    context 'when the CPU is jammed' do
      context 'and no interrupt is requested' do
        subject(:cpu) { described_class.new(bus:, program_counter: 0x8001).tap(&:jam) }

        before do
          bus.write(0x8001, 0xE8)
          allow(bus).to receive(:read).and_call_original
          allow(bus).to receive(:write).and_call_original
        end

        it 'reads and writes nothing', :aggregate_failures do
          cpu.step
          expect(bus).not_to have_received(:read)
          expect(bus).not_to have_received(:write)
        end

        it 'runs no instruction', :aggregate_failures do
          cpu.step
          expect(cpu.program_counter).to eq(0x8001)
          expect(cpu.index_x).to eq(0x00)
        end

        it 'takes 2 cycles, added to the count', :aggregate_failures do
          expect(cpu.step).to eq(2)
          expect(cpu.cycles).to eq(2)
        end
      end

      context 'and an NMI is pending' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8001, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.jam
            cpu.nmi_line_changed(true, 0)
          end
        end

        before { bus.write_bytes(0xFFFA, [0x34, 0x12]) }

        it 'takes no interrupt', :aggregate_failures do
          cpu.step
          expect(cpu.program_counter).to eq(0x8001)
          expect(cpu.stack.pointer).to eq(0xFD)
        end
      end

      context 'and the IRQ line is asserted with interrupt disable clear' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8001, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.jam
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 0)
          end
        end

        before { bus.write_bytes(0xFFFE, [0x34, 0x12]) }

        it 'takes no interrupt', :aggregate_failures do
          cpu.step
          expect(cpu.program_counter).to eq(0x8001)
          expect(cpu.stack.pointer).to eq(0xFD)
        end
      end
    end

    # The polling point (plan 12, decision 2): the CPU sees "the status of the interrupt lines at the end of the
    # second-to-last cycle", so an NMI edge on an instruction's last cycle waits for the next instruction.
    context 'when an NMI is pending' do
      context 'but its edge came on the last cycle of the previous instruction' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8123, cycles: 10).tap { |cpu| cpu.nmi_line_changed(true, 9) }
        end

        before do
          bus.write(0x8123, 0xE8)
          bus.write_bytes(0xFFFA, [0x34, 0x12])
        end

        it 'runs the instruction at the program counter', :aggregate_failures do
          expect(cpu.step).to eq(2)
          expect(cpu.index_x).to eq(0x01)
        end
      end

      context 'and its edge came before the last cycle of the previous instruction' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8123, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.status.carry = true
            cpu.nmi_line_changed(true, 8)
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
    end

    context 'when the IRQ line is asserted' do
      context 'but interrupt disable is set' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, cycles: 10).tap do |cpu|
            cpu.status.interrupt_disable = true
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 0)
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
          described_class.new(bus:, program_counter: 0x8123, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.status.carry = true
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 0)
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
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 0)
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

      # "The CLI, SEI, and PLP instructions on the other hand change the I flag after polling for interrupts", so
      # "executing CLI will execute the next instruction before the CPU invokes the IRQ handler", and an IRQ that comes
      # while SEI runs is still taken once (https://www.nesdev.org/wiki/CPU_interrupts).
      context 'and the previous instruction was CLI' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.status.interrupt_disable = true
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 0)
            cpu.step
          end
        end

        before do
          bus.write_bytes(0x8000, [0x58, 0xE8])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
        end

        it 'runs one more instruction before taking the IRQ', :aggregate_failures do
          expect(cpu.step).to eq(2)
          expect(cpu.step).to eq(7)
          expect(cpu.program_counter).to eq(0x1234)
        end
      end

      context 'and the previous instruction was SEI' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 9)
            cpu.step
          end
        end

        before do
          bus.write_bytes(0x8000, [0x78, 0xE8])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
        end

        it 'takes the IRQ', :aggregate_failures do
          expect(cpu.step).to eq(7)
          expect(cpu.program_counter).to eq(0x1234)
        end

        it 'pushes the flags with interrupt disable set' do
          cpu.step
          expect(bus.read(0x01FB)).to eq(0x24)
        end
      end

      context 'and the previous instruction was PLP, clearing interrupt disable' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.status.interrupt_disable = true
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 0)
            cpu.step
          end
        end

        before do
          bus.write(0x01FE, 0x00)
          bus.write_bytes(0x8000, [0x28, 0xE8])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
        end

        it 'runs one more instruction before taking the IRQ', :aggregate_failures do
          expect(cpu.step).to eq(2)
          expect(cpu.step).to eq(7)
          expect(cpu.program_counter).to eq(0x1234)
        end
      end

      # Branches poll "before the second CPU cycle (the operand fetch)", a taken branch not before the third, and one
      # that crosses a page also "before the PCH fixup cycle" (https://www.nesdev.org/wiki/CPU_interrupts).
      context 'and the line fell on the second cycle of a branch not taken' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 10)
            cpu.step
          end
        end

        before do
          bus.write_bytes(0x8000, [0xF0, 0x00, 0xE8])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
        end

        it 'takes the IRQ after the branch' do
          expect(cpu.step).to eq(7)
        end
      end

      context 'and the line fell on the second cycle of a taken branch that crossed no page' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 11)
            cpu.step
          end
        end

        before do
          bus.write_bytes(0x8000, [0xD0, 0x00, 0xE8])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
        end

        it 'runs one more instruction before taking the IRQ', :aggregate_failures do
          expect(cpu.step).to eq(2)
          expect(cpu.step).to eq(7)
        end
      end

      context 'and the line fell on the third cycle of a taken branch that crossed a page' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x80FD, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 12)
            cpu.step
          end
        end

        before do
          bus.write_bytes(0x80FD, [0xD0, 0x01])
          bus.write(0x8100, 0xE8)
          bus.write_bytes(0xFFFE, [0x34, 0x12])
        end

        it 'takes the IRQ after the branch' do
          expect(cpu.step).to eq(7)
        end
      end
    end

    # Interrupt hijacking (https://www.nesdev.org/wiki/CPU_interrupts): "if NMI is asserted during the first four ticks
    # of a BRK instruction, the BRK instruction will execute normally at first", then loads the NMI vector; "an NMI can
    # hijack an IRQ". The sequence asks its interrupt sync to catch the PPU up, so an edge by then is known (plan 22,
    # decision 1).
    context 'when an NMI edge comes during BRK' do
      context 'but after its fourth tick' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.interrupt_sync = interrupt_sync
          end
        end

        let(:interrupt_sync) { instance_double(Ruby::Nes::Console::PpuRegisterSync) }

        before do
          bus.write_bytes(0x8000, [0x00, 0x00])
          bus.write_bytes(0xFFFA, [0x78, 0x56])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
          bus.write(0x1234, 0xE8)
          allow(interrupt_sync).to receive(:catch_up) { cpu.nmi_line_changed(true, 14) }
        end

        # "The interrupt sequences themselves do not perform interrupt polling, meaning at least one instruction from
        # the interrupt handler will execute before another interrupt is serviced"
        # (https://www.nesdev.org/wiki/CPU_interrupts).
        it 'loads the IRQ vector, runs one handler instruction, then takes the NMI', :aggregate_failures do
          cpu.step
          expect(cpu.program_counter).to eq(0x1234)
          expect(cpu.step).to eq(2)
          cpu.step
          expect(cpu.program_counter).to eq(0x5678)
        end
      end

      context 'and by its fourth tick' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.interrupt_sync = interrupt_sync
          end
        end

        let(:interrupt_sync) { instance_double(Ruby::Nes::Console::PpuRegisterSync) }

        before do
          bus.write_bytes(0x8000, [0x00, 0x00])
          bus.write_bytes(0xFFFA, [0x78, 0x56])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
          bus.write(0x5678, 0xE8)
          allow(interrupt_sync).to receive(:catch_up) { cpu.nmi_line_changed(true, 13) }
        end

        it 'loads the program counter from the NMI vector, the flags pushed with break set', :aggregate_failures do
          cpu.step
          expect(cpu.program_counter).to eq(0x5678)
          expect(bus.read(0x01FB)).to eq(0x30)
        end

        it 'takes the NMI', :aggregate_failures do
          cpu.step
          expect(cpu.step).to eq(2)
          expect(cpu.program_counter).to eq(0x5679)
        end
      end
    end

    context 'when an NMI edge comes during the IRQ sequence' do
      context 'but after its fourth tick' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.interrupt_sync = interrupt_sync
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 0)
          end
        end

        let(:interrupt_sync) { instance_double(Ruby::Nes::Console::PpuRegisterSync) }

        before do
          bus.write(0x8000, 0xE8)
          bus.write_bytes(0xFFFA, [0x78, 0x56])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
          allow(interrupt_sync).to receive(:catch_up) { cpu.nmi_line_changed(true, 14) }
        end

        it 'loads the program counter from the IRQ vector' do
          cpu.step
          expect(cpu.program_counter).to eq(0x1234)
        end
      end

      context 'and by its fourth tick' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.interrupt_sync = interrupt_sync
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 0)
          end
        end

        let(:interrupt_sync) { instance_double(Ruby::Nes::Console::PpuRegisterSync) }

        before do
          bus.write(0x8000, 0xE8)
          bus.write_bytes(0xFFFA, [0x78, 0x56])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
          allow(interrupt_sync).to receive(:catch_up) { cpu.nmi_line_changed(true, 13) }
        end

        it 'loads the program counter from the NMI vector, the flags pushed with break clear', :aggregate_failures do
          cpu.step
          expect(cpu.program_counter).to eq(0x5678)
          expect(bus.read(0x01FB)).to eq(0x20)
        end
      end
    end

    # OAM DMA "halts the CPU" for "513 or 514 cycles" (https://www.nesdev.org/wiki/DMA); the bus reports the stall and
    # the step adds it (plan 11, decision 3), naming the cycle the halt falls on: the cycles run so far.
    context 'when the instruction makes the bus stall the CPU' do
      context 'and no interrupt line changes' do
        subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

        before do
          bus.write_bytes(0x8000, [0xEA])
          allow(bus).to receive(:take_stall_cycles).with(2).and_return(514)
        end

        it 'adds the stall to the cycles of the step and to the count', :aggregate_failures do
          expect(cpu.step).to eq(516)
          expect(cpu.cycles).to eq(516)
        end
      end

      # The CPU polled at the instruction's second-to-last cycle, before the DMA halted it, and polls nothing while
      # halted: an IRQ that comes during the stall waits for the next instruction's poll. cpu_interrupts_v2's
      # 4-irq_and_dma, written against the console, needs it (plan 22, decision 9).
      context 'and the IRQ line falls during the stall' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.step
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 100)
          end
        end

        before do
          bus.write_bytes(0x8000, [0xEA, 0xE8])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
          allow(bus).to receive(:take_stall_cycles).and_return(0)
          allow(bus).to receive(:take_stall_cycles).with(12).and_return(514)
        end

        it 'runs one more instruction before taking the IRQ', :aggregate_failures do
          expect(cpu.step).to eq(2)
          expect(cpu.step).to eq(7)
        end
      end
    end

    # Cpu#step charges an instruction's base cycles before running it (plan 12, decision 1), and the indexed reads add
    # their page-cross cycle while resolving the address, so at the data access the count is the cycle the instruction
    # ends on: the register sync catches the PPU up from it.
    context 'when the instruction accesses the bus' do
      context 'and it is a write' do
        subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, cycles: 10) }

        let(:probe) { double(cycles_seen: nil) }

        before do
          bus.write_bytes(0x8000, [0x8D, 0x00, 0x02])
          allow(bus).to receive(:write).and_invoke(->(_address, _value) { probe.cycles_seen(cpu.cycles) })
        end

        it 'counts the base cycles before the write' do
          cpu.step
          expect(probe).to have_received(:cycles_seen).with(14).once
        end
      end

      context 'and it is an indexed read crossing a page' do
        subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01, cycles: 10) }

        let(:probe) { double(cycles_seen: 0x00, dummy_read_at: 0x00) }

        before do
          bus.write_bytes(0x8000, [0xBD, 0xFF, 0x02])
          allow(bus).to receive(:read).and_call_original
          allow(bus).to receive(:read).with(0x0200).and_invoke(->(_address) { probe.dummy_read_at(cpu.cycles) })
          allow(bus).to receive(:read).with(0x0300).and_invoke(->(_address) { probe.cycles_seen(cpu.cycles) })
        end

        it 'counts the base and page-cross cycles before the read' do
          cpu.step
          expect(probe).to have_received(:cycles_seen).with(15).once
        end

        it 'makes the dummy read a cycle earlier, before the page-cross cycle counts' do
          cpu.step
          expect(probe).to have_received(:dummy_read_at).with(14).once
        end
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

    context 'when the opcode is $02 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x02]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $03 (SLO (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x03, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x81)
      end

      it 'writes $02 at $0200 and leaves $12 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0200)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $04 (NOP zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x04, 0x10])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0010 and moves past the operand in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(bus).to have_received(:read).with(0x0010)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $07 (SLO zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10) }

      before do
        bus.write_bytes(0x8000, [0x07, 0x10])
        bus.write(0x0010, 0x81)
      end

      it 'writes $02 at $0010 and leaves $12 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
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

    context 'when the opcode is $0B (ANC immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF0) }

      before { bus.write_bytes(0x8000, [0x0B, 0x80]) }

      it 'leaves $80 in the accumulator and sets carry in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x80)
        expect(cpu.status).to be_carry
      end
    end

    context 'when the opcode is $0C (NOP absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x0C, 0x00, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0200 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0200)
        expect(cpu.program_counter).to eq(0x8003)
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

    context 'when the opcode is $0F (SLO absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10) }

      before do
        bus.write_bytes(0x8000, [0x0F, 0x00, 0x02])
        bus.write(0x0200, 0x81)
      end

      it 'writes $02 at $0200 and leaves $12 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
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

    context 'when the opcode is $12 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x12]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $13 (SLO (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x13, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x81)
      end

      it 'writes $02 at $0205 and leaves $12 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0205)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $13 (SLO (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x13, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x81)
      end

      it 'writes $02 at $0300 and leaves $12 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0300)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $14 (NOP zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x14, 0x10])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0015 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0015)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $17 (SLO zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x17, 0x10])
        bus.write(0x0015, 0x81)
      end

      it 'writes $02 at $0015 and leaves $12 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
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

    context 'when the opcode is $1A (NOP)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x1A]) }

      it 'moves past the opcode only in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the opcode is $1B (SLO absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x1B, 0x00, 0x02])
        bus.write(0x0205, 0x81)
      end

      it 'writes $02 at $0205 and leaves $12 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $1B (SLO absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x1B, 0xFF, 0x02])
        bus.write(0x0300, 0x81)
      end

      it 'writes $02 at $0300 and leaves $12 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $1C (NOP absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x1C, 0x00, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0205 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0205)
        expect(cpu.program_counter).to eq(0x8003)
      end
    end

    context 'when the opcode is $1C (NOP absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x1C, 0xFF, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0300 and moves past the operand in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus).to have_received(:read).with(0x0300)
        expect(cpu.program_counter).to eq(0x8003)
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

    context 'when the opcode is $1F (SLO absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x1F, 0x00, 0x02])
        bus.write(0x0205, 0x81)
      end

      it 'writes $02 at $0205 and leaves $12 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $1F (SLO absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x1F, 0xFF, 0x02])
        bus.write(0x0300, 0x81)
      end

      it 'writes $02 at $0300 and leaves $12 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x02)
        expect(cpu.accumulator).to eq(0x12)
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

    context 'when the opcode is $22 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x22]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $23 (RLA (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x23, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0200 and leaves $03 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0200)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
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

    context 'when the opcode is $27 (RLA zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF) }

      before do
        bus.write_bytes(0x8000, [0x27, 0x10])
        bus.write(0x0010, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0010 and leaves $03 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
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

    context 'when the opcode is $2B (ANC immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF0) }

      before { bus.write_bytes(0x8000, [0x2B, 0x80]) }

      it 'leaves $80 in the accumulator and sets carry in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x80)
        expect(cpu.status).to be_carry
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

    context 'when the opcode is $2F (RLA absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF) }

      before do
        bus.write_bytes(0x8000, [0x2F, 0x00, 0x02])
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0200 and leaves $03 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
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

    context 'when the opcode is $32 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x32]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $33 (RLA (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x33, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0205 and leaves $03 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0205)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
      end
    end

    context 'when the opcode is $33 (RLA (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x33, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0300 and leaves $03 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0300)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
      end
    end

    context 'when the opcode is $34 (NOP zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x34, 0x10])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0015 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0015)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $37 (RLA zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x37, 0x10])
        bus.write(0x0015, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0015 and leaves $03 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
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

    context 'when the opcode is $3A (NOP)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x3A]) }

      it 'moves past the opcode only in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the opcode is $3B (RLA absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x3B, 0x00, 0x02])
        bus.write(0x0205, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0205 and leaves $03 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
      end
    end

    context 'when the opcode is $3B (RLA absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x3B, 0xFF, 0x02])
        bus.write(0x0300, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0300 and leaves $03 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
      end
    end

    context 'when the opcode is $3C (NOP absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x3C, 0x00, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0205 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0205)
        expect(cpu.program_counter).to eq(0x8003)
      end
    end

    context 'when the opcode is $3C (NOP absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x3C, 0xFF, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0300 and moves past the operand in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus).to have_received(:read).with(0x0300)
        expect(cpu.program_counter).to eq(0x8003)
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

    context 'when the opcode is $3F (RLA absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x3F, 0x00, 0x02])
        bus.write(0x0205, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0205 and leaves $03 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
      end
    end

    context 'when the opcode is $3F (RLA absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x3F, 0xFF, 0x02])
        bus.write(0x0300, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at $0300 and leaves $03 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x03)
        expect(cpu.accumulator).to eq(0x03)
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

    context 'when the opcode is $42 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x42]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $43 (SRE (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x43, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x03)
      end

      it 'writes $01 at $0200 and leaves $11 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0200)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
      end
    end

    context 'when the opcode is $44 (NOP zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x44, 0x10])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0010 and moves past the operand in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(bus).to have_received(:read).with(0x0010)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $47 (SRE zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10) }

      before do
        bus.write_bytes(0x8000, [0x47, 0x10])
        bus.write(0x0010, 0x03)
      end

      it 'writes $01 at $0010 and leaves $11 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
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

    context 'when the opcode is $4B (ALR immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF) }

      before { bus.write_bytes(0x8000, [0x4B, 0x03]) }

      it 'leaves $01 in the accumulator and sets carry in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x01)
        expect(cpu.status).to be_carry
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

    context 'when the opcode is $4F (SRE absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10) }

      before do
        bus.write_bytes(0x8000, [0x4F, 0x00, 0x02])
        bus.write(0x0200, 0x03)
      end

      it 'writes $01 at $0200 and leaves $11 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
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

    context 'when the opcode is $52 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x52]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $53 (SRE (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x53, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x03)
      end

      it 'writes $01 at $0205 and leaves $11 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0205)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
      end
    end

    context 'when the opcode is $53 (SRE (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x53, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x03)
      end

      it 'writes $01 at $0300 and leaves $11 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0300)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
      end
    end

    context 'when the opcode is $54 (NOP zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x54, 0x10])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0015 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0015)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $57 (SRE zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x57, 0x10])
        bus.write(0x0015, 0x03)
      end

      it 'writes $01 at $0015 and leaves $11 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
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

    context 'when the opcode is $5A (NOP)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x5A]) }

      it 'moves past the opcode only in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the opcode is $5B (SRE absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x5B, 0x00, 0x02])
        bus.write(0x0205, 0x03)
      end

      it 'writes $01 at $0205 and leaves $11 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
      end
    end

    context 'when the opcode is $5B (SRE absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x5B, 0xFF, 0x02])
        bus.write(0x0300, 0x03)
      end

      it 'writes $01 at $0300 and leaves $11 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
      end
    end

    context 'when the opcode is $5C (NOP absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x5C, 0x00, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0205 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0205)
        expect(cpu.program_counter).to eq(0x8003)
      end
    end

    context 'when the opcode is $5C (NOP absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x5C, 0xFF, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0300 and moves past the operand in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus).to have_received(:read).with(0x0300)
        expect(cpu.program_counter).to eq(0x8003)
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

    context 'when the opcode is $5F (SRE absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x5F, 0x00, 0x02])
        bus.write(0x0205, 0x03)
      end

      it 'writes $01 at $0205 and leaves $11 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
      end
    end

    context 'when the opcode is $5F (SRE absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x5F, 0xFF, 0x02])
        bus.write(0x0300, 0x03)
      end

      it 'writes $01 at $0300 and leaves $11 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x11)
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

    context 'when the opcode is $62 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x62]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $63 (RRA (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x63, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x03)
      end

      it 'writes $01 at $0200 and leaves $12 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0200)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $64 (NOP zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0x64, 0x10])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0010 and moves past the operand in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(bus).to have_received(:read).with(0x0010)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $67 (RRA zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10) }

      before do
        bus.write_bytes(0x8000, [0x67, 0x10])
        bus.write(0x0010, 0x03)
      end

      it 'writes $01 at $0010 and leaves $12 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
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

    context 'when the opcode is $6B (ARR immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF) }

      before { bus.write_bytes(0x8000, [0x6B, 0x80]) }

      it 'leaves $40 in the accumulator and sets overflow in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x40)
        expect(cpu.status).to be_overflow
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

    context 'when the opcode is $6F (RRA absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10) }

      before do
        bus.write_bytes(0x8000, [0x6F, 0x00, 0x02])
        bus.write(0x0200, 0x03)
      end

      it 'writes $01 at $0200 and leaves $12 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
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

    context 'when the opcode is $72 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x72]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $73 (RRA (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x73, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x03)
      end

      it 'writes $01 at $0205 and leaves $12 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0205)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $73 (RRA (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x73, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x03)
      end

      it 'writes $01 at $0300 and leaves $12 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0300)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $74 (NOP zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x74, 0x10])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0015 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0015)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $77 (RRA zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x77, 0x10])
        bus.write(0x0015, 0x03)
      end

      it 'writes $01 at $0015 and leaves $12 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
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

    context 'when the opcode is $7A (NOP)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x7A]) }

      it 'moves past the opcode only in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the opcode is $7B (RRA absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x7B, 0x00, 0x02])
        bus.write(0x0205, 0x03)
      end

      it 'writes $01 at $0205 and leaves $12 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $7B (RRA absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x7B, 0xFF, 0x02])
        bus.write(0x0300, 0x03)
      end

      it 'writes $01 at $0300 and leaves $12 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $7C (NOP absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x7C, 0x00, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0205 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0205)
        expect(cpu.program_counter).to eq(0x8003)
      end
    end

    context 'when the opcode is $7C (NOP absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x7C, 0xFF, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0300 and moves past the operand in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus).to have_received(:read).with(0x0300)
        expect(cpu.program_counter).to eq(0x8003)
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

    context 'when the opcode is $7F (RRA absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0x7F, 0x00, 0x02])
        bus.write(0x0205, 0x03)
      end

      it 'writes $01 at $0205 and leaves $12 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $7F (RRA absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x10, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0x7F, 0xFF, 0x02])
        bus.write(0x0300, 0x03)
      end

      it 'writes $01 at $0300 and leaves $12 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x01)
        expect(cpu.accumulator).to eq(0x12)
      end
    end

    context 'when the opcode is $80 (NOP immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x80, 0x42]) }

      it 'skips its operand in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $82 (NOP immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x82, 0x42]) }

      it 'skips its operand in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $83 (SAX (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0x83, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
      end

      it 'stores A AND X, $04, at $0200 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x04)
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

    context 'when the opcode is $87 (SAX zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF0, index_x: 0x3C) }

      before { bus.write_bytes(0x8000, [0x87, 0x10]) }

      it 'stores A AND X, $30, at $0010 in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(bus.read(0x0010)).to eq(0x30)
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

    context 'when the opcode is $89 (NOP immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x89, 0x42]) }

      it 'skips its operand in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $8B (XAA immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF, index_x: 0xF0) }

      before { bus.write_bytes(0x8000, [0x8B, 0x3C]) }

      it 'leaves $30 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x30)
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

    context 'when the opcode is $8F (SAX absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF0, index_x: 0x3C) }

      before { bus.write_bytes(0x8000, [0x8F, 0x00, 0x02]) }

      it 'stores A AND X, $30, at $0200 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus.read(0x0200)).to eq(0x30)
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

    context 'when the opcode is $92 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0x92]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $93 (AHX (indirect),Y)' do
      subject(:cpu) do
        described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF1, index_x: 0xFF, index_y: 0x05)
      end

      before do
        bus.write_bytes(0x8000, [0x93, 0x10])
        bus.write(0x0010, 0xF0)
        bus.write(0x0011, 0x12)
      end

      it 'stores A AND X AND $13, $11, at $12F5 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x12F5)).to eq(0x11)
      end
    end

    context 'when the opcode is $93 (AHX (indirect),Y) and the index crosses a page' do
      subject(:cpu) do
        described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF1, index_x: 0xFF, index_y: 0x20)
      end

      before do
        bus.write_bytes(0x8000, [0x93, 0x10])
        bus.write(0x0010, 0xF0)
        bus.write(0x0011, 0x12)
      end

      it 'stores A AND X AND $13, $11, on page $11, at $1110 in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x1110)).to eq(0x11)
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

    context 'when the opcode is $97 (SAX zero page,Y)' do
      subject(:cpu) do
        described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF0, index_x: 0x3C, index_y: 0x05)
      end

      before { bus.write_bytes(0x8000, [0x97, 0x10]) }

      it 'stores A AND X, $30, at $0015 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus.read(0x0015)).to eq(0x30)
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

    context 'when the opcode is $9B (TAS absolute,Y)' do
      subject(:cpu) do
        described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF0, index_x: 0x3F, index_y: 0x05)
      end

      before { bus.write_bytes(0x8000, [0x9B, 0xF0, 0x12]) }

      it 'moves $30 into the stack pointer and stores $10 at $12F5 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.stack.pointer).to eq(0x30)
        expect(bus.read(0x12F5)).to eq(0x10)
      end
    end

    context 'when the opcode is $9B (TAS absolute,Y) and the index crosses a page' do
      subject(:cpu) do
        described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF0, index_x: 0x3F, index_y: 0x20)
      end

      before { bus.write_bytes(0x8000, [0x9B, 0xF0, 0x12]) }

      it 'moves $30 into the stack pointer and stores $10 on page $10, at $1010 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu.stack.pointer).to eq(0x30)
        expect(bus.read(0x1010)).to eq(0x10)
      end
    end

    context 'when the opcode is $9C (SHY absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05, index_y: 0xF1) }

      before { bus.write_bytes(0x8000, [0x9C, 0xF0, 0x12]) }

      it 'stores Y AND $13, $11, at $12F5 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x12F5)).to eq(0x11)
      end
    end

    context 'when the opcode is $9C (SHY absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x20, index_y: 0xF1) }

      before { bus.write_bytes(0x8000, [0x9C, 0xF0, 0x12]) }

      it 'stores Y AND $13, $11, on page $11, at $1110 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x1110)).to eq(0x11)
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

    context 'when the opcode is $9E (SHX absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0xF1, index_y: 0x05) }

      before { bus.write_bytes(0x8000, [0x9E, 0xF0, 0x12]) }

      it 'stores X AND $13, $11, at $12F5 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x12F5)).to eq(0x11)
      end
    end

    context 'when the opcode is $9E (SHX absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0xF1, index_y: 0x20) }

      before { bus.write_bytes(0x8000, [0x9E, 0xF0, 0x12]) }

      it 'stores X AND $13, $11, on page $11, at $1110 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x1110)).to eq(0x11)
      end
    end

    context 'when the opcode is $9F (AHX absolute,Y)' do
      subject(:cpu) do
        described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF1, index_x: 0xFF, index_y: 0x05)
      end

      before { bus.write_bytes(0x8000, [0x9F, 0xF0, 0x12]) }

      it 'stores A AND X AND $13, $11, at $12F5 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x12F5)).to eq(0x11)
      end
    end

    context 'when the opcode is $9F (AHX absolute,Y) and the index crosses a page' do
      subject(:cpu) do
        described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF1, index_x: 0xFF, index_y: 0x20)
      end

      before { bus.write_bytes(0x8000, [0x9F, 0xF0, 0x12]) }

      it 'stores A AND X AND $13, $11, on page $11, at $1110 in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x1110)).to eq(0x11)
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

    context 'when the opcode is $A3 (LAX (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0xA3, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x42)
      end

      it 'loads $42 into the accumulator and X in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu).to have_attributes(accumulator: 0x42, index_x: 0x42)
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

    context 'when the opcode is $A7 (LAX zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xA7, 0x10])
        bus.write(0x0010, 0x42)
      end

      it 'loads $42 into the accumulator and X in 3 cycles', :aggregate_failures do
        expect(cpu.step).to eq(3)
        expect(cpu).to have_attributes(accumulator: 0x42, index_x: 0x42)
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

    context 'when the opcode is $AB (LAX immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xFF) }

      before { bus.write_bytes(0x8000, [0xAB, 0x81]) }

      it 'loads $81 into the accumulator and X in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to have_attributes(accumulator: 0x81, index_x: 0x81)
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

    context 'when the opcode is $AF (LAX absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before do
        bus.write_bytes(0x8000, [0xAF, 0x00, 0x02])
        bus.write(0x0200, 0x42)
      end

      it 'loads $42 into the accumulator and X in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu).to have_attributes(accumulator: 0x42, index_x: 0x42)
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

    context 'when the opcode is $B2 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xB2]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $B3 (LAX (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xB3, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x42)
      end

      it 'loads $42 into the accumulator and X in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu).to have_attributes(accumulator: 0x42, index_x: 0x42)
      end
    end

    context 'when the opcode is $B3 (LAX (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xB3, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x42)
      end

      it 'loads $42 into the accumulator and X in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(cpu).to have_attributes(accumulator: 0x42, index_x: 0x42)
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

    context 'when the opcode is $B7 (LAX zero page,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xB7, 0x10])
        bus.write(0x0015, 0x42)
      end

      it 'loads $42 into the accumulator and X in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu).to have_attributes(accumulator: 0x42, index_x: 0x42)
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

    context 'when the opcode is $BB (LAS absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x05, stack_pointer: 0x3C) }

      before do
        bus.write_bytes(0x8000, [0xBB, 0x00, 0x02])
        bus.write(0x0205, 0xF3)
      end

      it 'loads $30 into the accumulator, X and the stack pointer in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu).to have_attributes(accumulator: 0x30, index_x: 0x30)
        expect(cpu.stack.pointer).to eq(0x30)
      end
    end

    context 'when the opcode is $BB (LAS absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x01, stack_pointer: 0x3C) }

      before do
        bus.write_bytes(0x8000, [0xBB, 0xFF, 0x02])
        bus.write(0x0300, 0xF3)
      end

      it 'loads $30 into the accumulator, X and the stack pointer in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu).to have_attributes(accumulator: 0x30, index_x: 0x30)
        expect(cpu.stack.pointer).to eq(0x30)
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

    context 'when the opcode is $BF (LAX absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xBF, 0x00, 0x02])
        bus.write(0x0205, 0x42)
      end

      it 'loads $42 into the accumulator and X in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu).to have_attributes(accumulator: 0x42, index_x: 0x42)
      end
    end

    context 'when the opcode is $BF (LAX absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xBF, 0xFF, 0x02])
        bus.write(0x0300, 0x42)
      end

      it 'loads $42 into the accumulator and X in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(cpu).to have_attributes(accumulator: 0x42, index_x: 0x42)
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

    context 'when the opcode is $C2 (NOP immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xC2, 0x42]) }

      it 'skips its operand in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $C3 (DCP (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0xC3, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x11)
      end

      it 'writes $10 at $0200 and sets carry in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0200)).to eq(0x10)
        expect(cpu.status).to be_carry
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

    context 'when the opcode is $C7 (DCP zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20) }

      before do
        bus.write_bytes(0x8000, [0xC7, 0x10])
        bus.write(0x0010, 0x11)
      end

      it 'writes $10 at $0010 and sets carry in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x10)
        expect(cpu.status).to be_carry
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

    context 'when the opcode is $CB (AXS immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0xF0, index_x: 0x3C) }

      before { bus.write_bytes(0x8000, [0xCB, 0x10]) }

      it 'leaves $20 in X in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.index_x).to eq(0x20)
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

    context 'when the opcode is $CF (DCP absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20) }

      before do
        bus.write_bytes(0x8000, [0xCF, 0x00, 0x02])
        bus.write(0x0200, 0x11)
      end

      it 'writes $10 at $0200 and sets carry in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x10)
        expect(cpu.status).to be_carry
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

    context 'when the opcode is $D0 (BNE), zero is clear and the target is on the next page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x80F0) }

      before { bus.write_bytes(0x80F0, [0xD0, 0x10]) }

      it 'branches to $8102 in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(cpu.program_counter).to eq(0x8102)
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

    context 'when the opcode is $D2 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xD2]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $D3 (DCP (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xD3, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x11)
      end

      it 'writes $10 at $0205 and sets carry in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0205)).to eq(0x10)
        expect(cpu.status).to be_carry
      end
    end

    context 'when the opcode is $D3 (DCP (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xD3, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x11)
      end

      it 'writes $10 at $0300 and sets carry in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0300)).to eq(0x10)
        expect(cpu.status).to be_carry
      end
    end

    context 'when the opcode is $D4 (NOP zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xD4, 0x10])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0015 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0015)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $D7 (DCP zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xD7, 0x10])
        bus.write(0x0015, 0x11)
      end

      it 'writes $10 at $0015 and sets carry in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x10)
        expect(cpu.status).to be_carry
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

    context 'when the opcode is $DA (NOP)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xDA]) }

      it 'moves past the opcode only in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the opcode is $DB (DCP absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xDB, 0x00, 0x02])
        bus.write(0x0205, 0x11)
      end

      it 'writes $10 at $0205 and sets carry in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x10)
        expect(cpu.status).to be_carry
      end
    end

    context 'when the opcode is $DB (DCP absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xDB, 0xFF, 0x02])
        bus.write(0x0300, 0x11)
      end

      it 'writes $10 at $0300 and sets carry in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x10)
        expect(cpu.status).to be_carry
      end
    end

    context 'when the opcode is $DC (NOP absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xDC, 0x00, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0205 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0205)
        expect(cpu.program_counter).to eq(0x8003)
      end
    end

    context 'when the opcode is $DC (NOP absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xDC, 0xFF, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0300 and moves past the operand in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus).to have_received(:read).with(0x0300)
        expect(cpu.program_counter).to eq(0x8003)
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

    context 'when the opcode is $DF (DCP absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xDF, 0x00, 0x02])
        bus.write(0x0205, 0x11)
      end

      it 'writes $10 at $0205 and sets carry in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x10)
        expect(cpu.status).to be_carry
      end
    end

    context 'when the opcode is $DF (DCP absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xDF, 0xFF, 0x02])
        bus.write(0x0300, 0x11)
      end

      it 'writes $10 at $0300 and sets carry in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x10)
        expect(cpu.status).to be_carry
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

    context 'when the opcode is $E2 (NOP immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xE2, 0x42]) }

      it 'skips its operand in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the opcode is $E3 (ISB (indirect,X))' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_x: 0x04) }

      before do
        bus.write_bytes(0x8000, [0xE3, 0x10])
        bus.write(0x0014, 0x00)
        bus.write(0x0015, 0x02)
        bus.write(0x0200, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0200 and leaves $10 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0200)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
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

    context 'when the opcode is $E7 (ISB zero page)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20) }

      before do
        bus.write_bytes(0x8000, [0xE7, 0x10])
        bus.write(0x0010, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0010 and leaves $10 in the accumulator in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus.read(0x0010)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
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

    context 'when the opcode is $EB (SBC immediate)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20) }

      before do
        bus.write_bytes(0x8000, [0xEB, 0x10])
        cpu.status.restore(0x01)
      end

      it 'leaves $10 in the accumulator in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.accumulator).to eq(0x10)
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

    context 'when the opcode is $EF (ISB absolute)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20) }

      before do
        bus.write_bytes(0x8000, [0xEF, 0x00, 0x02])
        bus.write(0x0200, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0200 and leaves $10 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0200)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
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

    context 'when the opcode is $F2 (JAM)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xF2]) }

      it 'jams the CPU in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu).to be_jammed
      end
    end

    context 'when the opcode is $F3 (ISB (indirect),Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xF3, 0x10])
        bus.write(0x0010, 0x00)
        bus.write(0x0011, 0x02)
        bus.write(0x0205, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0205 and leaves $10 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0205)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
      end
    end

    context 'when the opcode is $F3 (ISB (indirect),Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xF3, 0x10])
        bus.write(0x0010, 0xFF)
        bus.write(0x0011, 0x02)
        bus.write(0x0300, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0300 and leaves $10 in the accumulator in 8 cycles', :aggregate_failures do
        expect(cpu.step).to eq(8)
        expect(bus.read(0x0300)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
      end
    end

    context 'when the opcode is $F4 (NOP zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xF4, 0x10])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0015 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0015)
        expect(cpu.program_counter).to eq(0x8002)
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

    context 'when the opcode is $F7 (ISB zero page,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xF7, 0x10])
        bus.write(0x0015, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0015 and leaves $10 in the accumulator in 6 cycles', :aggregate_failures do
        expect(cpu.step).to eq(6)
        expect(bus.read(0x0015)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
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

    context 'when the opcode is $FA (NOP)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000) }

      before { bus.write_bytes(0x8000, [0xFA]) }

      it 'moves past the opcode only in 2 cycles', :aggregate_failures do
        expect(cpu.step).to eq(2)
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the opcode is $FB (ISB absolute,Y)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_y: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xFB, 0x00, 0x02])
        bus.write(0x0205, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0205 and leaves $10 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
      end
    end

    context 'when the opcode is $FB (ISB absolute,Y) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_y: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xFB, 0xFF, 0x02])
        bus.write(0x0300, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0300 and leaves $10 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
      end
    end

    context 'when the opcode is $FC (NOP absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xFC, 0x00, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0205 and moves past the operand in 4 cycles', :aggregate_failures do
        expect(cpu.step).to eq(4)
        expect(bus).to have_received(:read).with(0x0205)
        expect(cpu.program_counter).to eq(0x8003)
      end
    end

    context 'when the opcode is $FC (NOP absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xFC, 0xFF, 0x02])
        allow(bus).to receive(:read).and_call_original
      end

      it 'reads $0300 and moves past the operand in 5 cycles', :aggregate_failures do
        expect(cpu.step).to eq(5)
        expect(bus).to have_received(:read).with(0x0300)
        expect(cpu.program_counter).to eq(0x8003)
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

    context 'when the opcode is $FF (ISB absolute,X)' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_x: 0x05) }

      before do
        bus.write_bytes(0x8000, [0xFF, 0x00, 0x02])
        bus.write(0x0205, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0205 and leaves $10 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0205)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
      end
    end

    context 'when the opcode is $FF (ISB absolute,X) and the index crosses a page' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, accumulator: 0x20, index_x: 0x01) }

      before do
        bus.write_bytes(0x8000, [0xFF, 0xFF, 0x02])
        bus.write(0x0300, 0x0F)
        cpu.status.restore(0x01)
      end

      it 'writes $10 at $0300 and leaves $10 in the accumulator in 7 cycles', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(bus.read(0x0300)).to eq(0x10)
        expect(cpu.accumulator).to eq(0x10)
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
