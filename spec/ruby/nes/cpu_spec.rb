# frozen_string_literal: true

# CPU registers (https://www.nesdev.org/wiki/CPU_registers): A, X, Y and S are byte-wide; "The 2-byte program counter
# PC supports 65536 direct (unbanked) memory locations", so it wraps from $FFFF to $0000. Operands are little-endian.
RSpec.describe Ruby::Nes::Cpu do
  describe '.new' do
    context 'when only the bus is given' do
      it 'starts every register at zero, not jammed', :aggregate_failures do
        cpu = described_class.new(bus: FlatBus.new)

        expect(cpu.accumulator).to eq(0x00)
        expect(cpu.index_x).to eq(0x00)
        expect(cpu.index_y).to eq(0x00)
        expect(cpu.program_counter).to eq(0x0000)
        expect(cpu.stack.pointer).to eq(0x00)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
        expect(cpu.cycles).to eq(0)
        expect(cpu).not_to be_jammed
      end
    end

    context 'with a stack pointer' do
      it 'starts the stack at that pointer' do
        cpu = described_class.new(bus: FlatBus.new, stack_pointer: 0xFD)

        expect(cpu.stack.pointer).to eq(0xFD)
      end
    end
  end

  # Cpu#step charges an instruction's cycles before running it, and every non-read-modify-write instruction makes its
  # data access on its last cycle (https://www.nesdev.org/6502_cpu.txt): the one before the cycle it ends on (plan 12,
  # decision 1).
  describe '#access_cycle' do
    context 'when the instruction running ends on cycle 30' do
      subject(:cpu) { described_class.new(bus: FlatBus.new, cycles: 30) }

      it 'returns cycle 29' do
        expect(cpu.access_cycle).to eq(29)
      end
    end
  end

  # "DMC DMA halts the CPU, performs a dummy cycle and an optional alignment cycle, and then gets once, taking 3 or 4
  # cycles" (https://www.nesdev.org/wiki/DMA): the DMC halts the CPU on the cycle it fetches (plan 23, decision 1). The
  # halted CPU polls nothing, so the next poll looks back past the stall (plan 22, decision 9).
  describe '#halt' do
    context 'when the CPU is between steps' do
      context 'and no interrupt line changes' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, accumulator: 0x42, stack_pointer: 0xFD, cycles: 10)
        end

        let(:bus) { FlatBus.new }

        before do
          allow(bus).to receive(:read).and_call_original
          allow(bus).to receive(:write).and_call_original
        end

        it 'adds the stall to the cycle count, leaving registers and bus untouched', :aggregate_failures do
          cpu.halt(4)

          expect(cpu.cycles).to eq(14)
          expect(cpu).to have_attributes(program_counter: 0x8000, accumulator: 0x42)
          expect(bus).not_to have_received(:read)
          expect(bus).not_to have_received(:write)
        end
      end

      context 'and the IRQ line falls during the stall' do
        subject(:cpu) do
          described_class.new(bus:, program_counter: 0x8000, stack_pointer: 0xFD, cycles: 10).tap do |cpu|
            cpu.step
            cpu.halt(4)
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ, 14)
          end
        end

        let(:bus) { FlatBus.new }

        before do
          bus.write_bytes(0x8000, [0xEA, 0xE8])
          bus.write_bytes(0xFFFE, [0x34, 0x12])
        end

        it 'runs one more instruction before taking the IRQ', :aggregate_failures do
          expect(cpu.step).to eq(2)
          expect(cpu.step).to eq(7)
        end
      end
    end

    context 'when a device halts it during an instruction' do
      subject(:cpu) { described_class.new(bus:, program_counter: 0x8000, cycles: 10) }

      let(:bus) { FlatBus.new }

      before do
        # STA $4015, whose write the device answers with a 3-cycle halt.
        bus.write_bytes(0x8000, [0x8D, 0x15, 0x40])
        allow(bus).to receive(:write).and_call_original
        allow(bus).to receive(:write).with(0x4015, anything) { cpu.halt(3) }
      end

      it 'counts the stall in the cycles of the step', :aggregate_failures do
        expect(cpu.step).to eq(7)
        expect(cpu.cycles).to eq(17)
      end
    end
  end

  describe '#fetch_byte' do
    subject(:cpu) { described_class.new(bus:, program_counter:) }

    let(:bus) { FlatBus.new }

    context 'when the program counter is $8000' do
      let(:program_counter) { 0x8000 }

      before { bus.write(0x8000, 0x5A) }

      it 'returns the byte at $8000' do
        expect(cpu.fetch_byte).to eq(0x5A)
      end

      it 'advances the program counter to $8001' do
        cpu.fetch_byte
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the program counter is $FFFF' do
      let(:program_counter) { 0xFFFF }

      before { bus.write(0xFFFF, 0x5A) }

      it 'returns the byte at $FFFF' do
        expect(cpu.fetch_byte).to eq(0x5A)
      end

      it 'wraps the program counter to $0000' do
        cpu.fetch_byte
        expect(cpu.program_counter).to eq(0x0000)
      end
    end
  end

  describe '#fetch_word' do
    subject(:cpu) { described_class.new(bus:, program_counter:) }

    let(:bus) { FlatBus.new }

    context 'when the program counter is $8000' do
      let(:program_counter) { 0x8000 }

      before do
        bus.write(0x8000, 0xAB)
        bus.write(0x8001, 0x12)
      end

      it 'combines the low byte at $8000 with the high byte at $8001' do
        expect(cpu.fetch_word).to eq(0x12AB)
      end

      it 'advances the program counter to $8002' do
        cpu.fetch_word
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the program counter is $FFFF' do
      let(:program_counter) { 0xFFFF }

      before do
        bus.write(0xFFFF, 0xAB)
        bus.write(0x0000, 0x12)
      end

      it 'combines the low byte at $FFFF with the high byte at $0000' do
        expect(cpu.fetch_word).to eq(0x12AB)
      end

      it 'wraps the program counter to $0001' do
        cpu.fetch_word
        expect(cpu.program_counter).to eq(0x0001)
      end
    end
  end
end
