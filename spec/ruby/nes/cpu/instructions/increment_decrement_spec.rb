# frozen_string_literal: true

# Increments and decrements (https://www.nesdev.org/wiki/Instruction_reference): INC and DEC change the byte at the
# effective address, INX, INY, DEX and DEY a register, by one, wrapping within a byte. They set Z ("result == 0") and N
# ("result bit 7") and do "_not_ affect carry nor overflow".
RSpec.describe Ruby::Nes::Cpu::Instructions::IncrementDecrement do
  describe '#increment_memory' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

    let(:bus) { FlatBus.new }

    context 'when the byte at the address is $01' do
      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x82)
      end

      it 'changes it to $02' do
        cpu.increment_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0x02)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.increment_memory(0x0200)
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte at the address is $7F' do
      before do
        bus.write(0x0200, 0x7F)
        cpu.status.restore(0x02)
      end

      it 'changes it to $80' do
        cpu.increment_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0x80)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.increment_memory(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when the byte at the address is $FF' do
      before do
        bus.write(0x0200, 0xFF)
        cpu.status.restore(0x80)
      end

      it 'wraps it to $00' do
        cpu.increment_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0x00)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.increment_memory(0x0200)
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      before do
        bus.write(0x0200, 0x10)
        cpu.status.restore(0x4D)
      end

      it 'leaves them set' do
        cpu.increment_memory(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#increment_index_x' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, index_x:) }

    context 'when X is $01' do
      let(:index_x) { 0x01 }

      before { cpu.status.restore(0x82) }

      it 'changes it to $02' do
        cpu.increment_index_x
        expect(cpu.index_x).to eq(0x02)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.increment_index_x
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when X is $7F' do
      let(:index_x) { 0x7F }

      before { cpu.status.restore(0x02) }

      it 'changes it to $80' do
        cpu.increment_index_x
        expect(cpu.index_x).to eq(0x80)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.increment_index_x
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when X is $FF' do
      let(:index_x) { 0xFF }

      before { cpu.status.restore(0x80) }

      it 'wraps it to $00' do
        cpu.increment_index_x
        expect(cpu.index_x).to eq(0x00)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.increment_index_x
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:index_x) { 0x10 }

      before { cpu.status.restore(0x4D) }

      it 'leaves them set' do
        cpu.increment_index_x
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#increment_index_y' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, index_y:) }

    context 'when Y is $01' do
      let(:index_y) { 0x01 }

      before { cpu.status.restore(0x82) }

      it 'changes it to $02' do
        cpu.increment_index_y
        expect(cpu.index_y).to eq(0x02)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.increment_index_y
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when Y is $7F' do
      let(:index_y) { 0x7F }

      before { cpu.status.restore(0x02) }

      it 'changes it to $80' do
        cpu.increment_index_y
        expect(cpu.index_y).to eq(0x80)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.increment_index_y
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when Y is $FF' do
      let(:index_y) { 0xFF }

      before { cpu.status.restore(0x80) }

      it 'wraps it to $00' do
        cpu.increment_index_y
        expect(cpu.index_y).to eq(0x00)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.increment_index_y
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:index_y) { 0x10 }

      before { cpu.status.restore(0x4D) }

      it 'leaves them set' do
        cpu.increment_index_y
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#decrement_memory' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:) }

    let(:bus) { FlatBus.new }

    context 'when the byte at the address is $02' do
      before do
        bus.write(0x0200, 0x02)
        cpu.status.restore(0x82)
      end

      it 'changes it to $01' do
        cpu.decrement_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.decrement_memory(0x0200)
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte at the address is $01' do
      before do
        bus.write(0x0200, 0x01)
        cpu.status.restore(0x80)
      end

      it 'changes it to $00' do
        cpu.decrement_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0x00)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.decrement_memory(0x0200)
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when the byte at the address is $00' do
      before do
        bus.write(0x0200, 0x00)
        cpu.status.restore(0x02)
      end

      it 'wraps it to $FF' do
        cpu.decrement_memory(0x0200)
        expect(bus.read(0x0200)).to eq(0xFF)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.decrement_memory(0x0200)
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      before do
        bus.write(0x0200, 0x10)
        cpu.status.restore(0x4D)
      end

      it 'leaves them set' do
        cpu.decrement_memory(0x0200)
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#decrement_index_x' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, index_x:) }

    context 'when X is $02' do
      let(:index_x) { 0x02 }

      before { cpu.status.restore(0x82) }

      it 'changes it to $01' do
        cpu.decrement_index_x
        expect(cpu.index_x).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.decrement_index_x
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when X is $01' do
      let(:index_x) { 0x01 }

      before { cpu.status.restore(0x80) }

      it 'changes it to $00' do
        cpu.decrement_index_x
        expect(cpu.index_x).to eq(0x00)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.decrement_index_x
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when X is $00' do
      let(:index_x) { 0x00 }

      before { cpu.status.restore(0x02) }

      it 'wraps it to $FF' do
        cpu.decrement_index_x
        expect(cpu.index_x).to eq(0xFF)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.decrement_index_x
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:index_x) { 0x10 }

      before { cpu.status.restore(0x4D) }

      it 'leaves them set' do
        cpu.decrement_index_x
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end

  describe '#decrement_index_y' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, index_y:) }

    context 'when Y is $02' do
      let(:index_y) { 0x02 }

      before { cpu.status.restore(0x82) }

      it 'changes it to $01' do
        cpu.decrement_index_y
        expect(cpu.index_y).to eq(0x01)
      end

      it 'clears zero and negative', :aggregate_failures do
        cpu.decrement_index_y
        expect(cpu.status).not_to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when Y is $01' do
      let(:index_y) { 0x01 }

      before { cpu.status.restore(0x80) }

      it 'changes it to $00' do
        cpu.decrement_index_y
        expect(cpu.index_y).to eq(0x00)
      end

      it 'sets zero and clears negative', :aggregate_failures do
        cpu.decrement_index_y
        expect(cpu.status).to be_zero
        expect(cpu.status).not_to be_negative
      end
    end

    context 'when Y is $00' do
      let(:index_y) { 0x00 }

      before { cpu.status.restore(0x02) }

      it 'wraps it to $FF' do
        cpu.decrement_index_y
        expect(cpu.index_y).to eq(0xFF)
      end

      it 'sets negative and clears zero', :aggregate_failures do
        cpu.decrement_index_y
        expect(cpu.status).to be_negative
        expect(cpu.status).not_to be_zero
      end
    end

    context 'when carry, interrupt disable, decimal and overflow are set' do
      let(:index_y) { 0x10 }

      before { cpu.status.restore(0x4D) }

      it 'leaves them set' do
        cpu.decrement_index_y
        expect(cpu.status.byte_pushed_by_interrupt).to eq(0x6D)
      end
    end
  end
end
