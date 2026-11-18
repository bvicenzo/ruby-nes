# frozen_string_literal: true

# Stack (https://www.nesdev.org/wiki/Stack): page $0100-$01FF, descending and empty: "if S = $FD, and the program
# pushes something, it'll be written to $01FD and then S becomes $FC". S is byte-wide
# (https://www.nesdev.org/wiki/CPU_registers), so it wraps both ways. 16-bit values are pushed high byte first (JSR,
# https://www.nesdev.org/wiki/Instruction_reference).
RSpec.describe Ruby::Nes::Cpu::Stack do
  describe '.new' do
    context 'when no pointer is given' do
      it 'points at $00' do
        expect(described_class.new(bus: FlatBus.new).pointer).to eq(0x00)
      end
    end
  end

  describe '#push' do
    subject(:stack) { described_class.new(bus:, pointer:) }

    let(:bus) { FlatBus.new }

    context 'when the pointer is $FD' do
      let(:pointer) { 0xFD }

      it 'writes the value at $01FD' do
        stack.push(0x5A)
        expect(bus.read(0x01FD)).to eq(0x5A)
      end

      it 'moves the pointer to $FC' do
        stack.push(0x5A)
        expect(stack.pointer).to eq(0xFC)
      end
    end

    context 'when the pointer is $00' do
      let(:pointer) { 0x00 }

      it 'writes the value at $0100' do
        stack.push(0x5A)
        expect(bus.read(0x0100)).to eq(0x5A)
      end

      it 'wraps the pointer to $FF' do
        stack.push(0x5A)
        expect(stack.pointer).to eq(0xFF)
      end
    end
  end

  describe '#pull' do
    subject(:stack) { described_class.new(bus:, pointer:) }

    let(:bus) { FlatBus.new }

    context 'when the pointer is $FC' do
      let(:pointer) { 0xFC }

      before { bus.write(0x01FD, 0x5A) }

      it 'returns the byte at $01FD' do
        expect(stack.pull).to eq(0x5A)
      end

      it 'moves the pointer to $FD' do
        stack.pull
        expect(stack.pointer).to eq(0xFD)
      end
    end

    context 'when the pointer is $FF' do
      let(:pointer) { 0xFF }

      before { bus.write(0x0100, 0x5A) }

      it 'returns the byte at $0100' do
        expect(stack.pull).to eq(0x5A)
      end

      it 'wraps the pointer to $00' do
        stack.pull
        expect(stack.pointer).to eq(0x00)
      end
    end
  end

  describe '#push_word' do
    subject(:stack) { described_class.new(bus:, pointer: 0xFD) }

    let(:bus) { FlatBus.new }

    it 'writes the high byte at $01FD and the low byte at $01FC', :aggregate_failures do
      stack.push_word(0x12AB)

      expect(bus.read(0x01FD)).to eq(0x12)
      expect(bus.read(0x01FC)).to eq(0xAB)
    end

    it 'moves the pointer to $FB' do
      stack.push_word(0x12AB)
      expect(stack.pointer).to eq(0xFB)
    end
  end

  describe '#pull_word' do
    subject(:stack) { described_class.new(bus:, pointer: 0xFB) }

    let(:bus) { FlatBus.new }

    before do
      bus.write(0x01FC, 0xAB)
      bus.write(0x01FD, 0x12)
    end

    it 'combines the low byte from $01FC with the high byte from $01FD' do
      expect(stack.pull_word).to eq(0x12AB)
    end

    it 'moves the pointer to $FD' do
      stack.pull_word
      expect(stack.pointer).to eq(0xFD)
    end
  end
end
