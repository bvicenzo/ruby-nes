# frozen_string_literal: true

# ASL, LSR, ROL and ROR (https://www.nesdev.org/wiki/Instruction_reference) on the accumulator or on the byte at the
# effective address. The operations themselves (carry, Z, N) are specified in Cpu::Shifter; here, only where the
# result goes. With $81 and the carry set the four operations give four different bytes: ASL $02, LSR $40, ROL $03,
# ROR $C0.
RSpec.describe Ruby::Nes::Cpu::Instructions::Shifts do
  describe '#shift_left_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, accumulator: 0x81) }

    context 'when the accumulator is $81 and the carry is set' do
      before { cpu.status.restore(0x01) }

      it 'leaves $02 in the accumulator' do
        cpu.shift_left_accumulator
        expect(cpu.accumulator).to eq(0x02)
      end
    end
  end

  describe '#shift_left_memory' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

    let(:bus) { FlatBus.new }

    context 'when the byte at the address is $81 and the carry is set' do
      before do
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $02 at the address' do
        cpu.shift_left_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0x02)
      end
    end
  end

  describe '#shift_right_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, accumulator: 0x81) }

    context 'when the accumulator is $81 and the carry is set' do
      before { cpu.status.restore(0x01) }

      it 'leaves $40 in the accumulator' do
        cpu.shift_right_accumulator
        expect(cpu.accumulator).to eq(0x40)
      end
    end
  end

  describe '#shift_right_memory' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

    let(:bus) { FlatBus.new }

    context 'when the byte at the address is $81 and the carry is set' do
      before do
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $40 at the address' do
        cpu.shift_right_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0x40)
      end
    end
  end

  describe '#rotate_left_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, accumulator: 0x81) }

    context 'when the accumulator is $81 and the carry is set' do
      before { cpu.status.restore(0x01) }

      it 'leaves $03 in the accumulator' do
        cpu.rotate_left_accumulator
        expect(cpu.accumulator).to eq(0x03)
      end
    end
  end

  describe '#rotate_left_memory' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

    let(:bus) { FlatBus.new }

    context 'when the byte at the address is $81 and the carry is set' do
      before do
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $03 at the address' do
        cpu.rotate_left_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0x03)
      end
    end
  end

  describe '#rotate_right_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, accumulator: 0x81) }

    context 'when the accumulator is $81 and the carry is set' do
      before { cpu.status.restore(0x01) }

      it 'leaves $C0 in the accumulator' do
        cpu.rotate_right_accumulator
        expect(cpu.accumulator).to eq(0xC0)
      end
    end
  end

  describe '#rotate_right_memory' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

    let(:bus) { FlatBus.new }

    context 'when the byte at the address is $81 and the carry is set' do
      before do
        bus.write(0x0200, 0x81)
        cpu.status.restore(0x01)
      end

      it 'writes $C0 at the address' do
        cpu.rotate_right_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0xC0)
      end
    end
  end
end
