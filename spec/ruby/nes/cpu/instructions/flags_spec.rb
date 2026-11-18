# frozen_string_literal: true

# Flag instructions (https://www.nesdev.org/wiki/Instruction_reference): CLC, CLD, CLI and CLV clear one flag; SEC, SED
# and SEI set one. No other flag changes. The status is observed through the byte an interrupt would push (bit 5 set,
# B clear), so "every flag set" reads $EF.
RSpec.describe Ruby::Nes::Cpu::Instructions::Flags do
  describe '#clear_carry' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new) }

    context 'when every flag is set' do
      before { cpu.status.restore(0xFF) }

      it 'clears carry only' do
        cpu.clear_carry
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0xEE)
      end
    end
  end

  describe '#clear_decimal' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new) }

    context 'when every flag is set' do
      before { cpu.status.restore(0xFF) }

      it 'clears decimal only' do
        cpu.clear_decimal
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0xE7)
      end
    end
  end

  describe '#clear_interrupt_disable' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new) }

    context 'when every flag is set' do
      before { cpu.status.restore(0xFF) }

      it 'clears interrupt disable only' do
        cpu.clear_interrupt_disable
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0xEB)
      end
    end
  end

  describe '#clear_overflow' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new) }

    context 'when every flag is set' do
      before { cpu.status.restore(0xFF) }

      it 'clears overflow only' do
        cpu.clear_overflow
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0xAF)
      end
    end
  end

  describe '#set_carry' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new) }

    context 'when every flag is clear' do
      it 'sets carry only' do
        cpu.set_carry
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x21)
      end
    end
  end

  describe '#set_decimal' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new) }

    context 'when every flag is clear' do
      it 'sets decimal only' do
        cpu.set_decimal
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x28)
      end
    end
  end

  describe '#set_interrupt_disable' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new) }

    context 'when every flag is clear' do
      it 'sets interrupt disable only' do
        cpu.set_interrupt_disable
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x24)
      end
    end
  end
end
