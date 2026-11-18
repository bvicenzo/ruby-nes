# frozen_string_literal: true

# CPU registers (https://www.nesdev.org/wiki/CPU_registers): A, X, Y and S are byte-wide; "The 2-byte program counter
# PC supports 65536 direct (unbanked) memory locations", so it wraps from $FFFF to $0000. Operands are little-endian.
RSpec.describe Ruby::Nes::Cpu do
  describe '.new' do
    context 'when only the bus is given' do
      it 'starts every register at zero', :aggregate_failures do
        cpu = described_class.new(bus: FlatBus.new)

        expect(cpu.accumulator).to eq(0x00)
        expect(cpu.index_x).to eq(0x00)
        expect(cpu.index_y).to eq(0x00)
        expect(cpu.program_counter).to eq(0x0000)
        expect(cpu.stack.pointer).to eq(0x00)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
        expect(cpu.cycles).to eq(0)
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
