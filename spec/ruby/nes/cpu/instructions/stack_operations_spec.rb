# frozen_string_literal: true

# Stack instructions (https://www.nesdev.org/wiki/Instruction_reference): PHA pushes A; PHP pushes P with "The B flag
# and extra bit are both pushed as 1"; PLA pulls into A and sets Z and N; PLP pulls into P and "The B flag and extra
# bit are ignored". The stack is descending and empty (https://www.nesdev.org/wiki/Stack): a push at S = $FD writes
# $01FD and leaves S = $FC.
RSpec.describe Ruby::Nes::Cpu::Instructions::StackOperations do
  describe '#push_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator:, stack_pointer: 0xFD) }

    let(:bus) { FlatBus.new }

    context 'when the accumulator is $00' do
      let(:accumulator) { 0x00 }

      before { bus.write(0x01FD, 0xFF) }

      it 'writes $00 at $01FD' do
        cpu.push_accumulator
        expect(bus.read(0x01FD)).to eq(0x00)
      end

      it 'moves the stack pointer to $FC' do
        cpu.push_accumulator
        expect(cpu.stack.pointer).to eq(0xFC)
      end

      it 'leaves the status unchanged' do
        cpu.push_accumulator
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end
  end

  describe '#push_status' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, stack_pointer: 0xFD) }

    let(:bus) { FlatBus.new }

    context 'when every flag is clear' do
      it 'writes $30 at $01FD' do
        cpu.push_status
        expect(bus.read(0x01FD)).to eq(0x30)
      end

      it 'moves the stack pointer to $FC' do
        cpu.push_status
        expect(cpu.stack.pointer).to eq(0xFC)
      end
    end

    context 'when carry and negative are set' do
      before { cpu.status.restore(0x81) }

      it 'writes $B1 at $01FD' do
        cpu.push_status
        expect(bus.read(0x01FD)).to eq(0xB1)
      end
    end
  end

  describe '#pull_accumulator' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, stack_pointer: 0xFC) }

    let(:bus) { FlatBus.new }

    context 'when the byte on top of the stack is $01' do
      before do
        bus.write(0x01FD, 0x01)
        cpu.status.restore(0x82)
      end

      it 'loads $01 into the accumulator' do
        cpu.pull_accumulator
        expect(cpu.accumulator).to eq(0x01)
      end

      it 'moves the stack pointer to $FD' do
        cpu.pull_accumulator
        expect(cpu.stack.pointer).to eq(0xFD)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.pull_accumulator
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte on top of the stack is $00' do
      before do
        bus.write(0x01FD, 0x00)
        cpu.status.restore(0x80)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.pull_accumulator
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte on top of the stack is $80' do
      before do
        bus.write(0x01FD, 0x80)
        cpu.status.restore(0x02)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.pull_accumulator
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      before do
        bus.write(0x01FD, 0x01)
        cpu.status.restore(0x4D)
      end

      it 'leaves them set' do
        cpu.pull_accumulator
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#pull_status' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, stack_pointer: 0xFC) }

    let(:bus) { FlatBus.new }

    context 'when the byte on top of the stack is $FF' do
      before { bus.write(0x01FD, 0xFF) }

      it 'sets every flag but break' do
        cpu.pull_status
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0xEF)
      end

      it 'moves the stack pointer to $FD' do
        cpu.pull_status
        expect(cpu.stack.pointer).to eq(0xFD)
      end
    end

    context 'when the byte on top of the stack is $00' do
      before do
        bus.write(0x01FD, 0x00)
        cpu.status.restore(0xCF)
      end

      it 'clears every flag' do
        cpu.pull_status
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x20)
      end
    end
  end
end
