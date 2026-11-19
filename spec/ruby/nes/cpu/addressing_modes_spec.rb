# frozen_string_literal: true

# CPU addressing modes (https://www.nesdev.org/wiki/CPU_addressing_modes): zero page indexed is `PEEK((arg + X) % 256)`;
# "(d,x)" reads its pointer at `(arg + X) % 256` and `(arg + X + 1) % 256`; "(d),y" at `arg` and `(arg + 1) % 256`;
# absolute indexed and "(d),y" add a cycle "for page wrapping on read instructions". Indirect JMP: "JMP ($03FF) reads
# $03FF and $0300 instead of $0400"; branch offsets are signed and "relative to the first byte after the branch
# instruction" (https://www.nesdev.org/wiki/Instruction_reference). Addresses are 16 bits wide and wrap past $FFFF
# (plan 05, decision 6); a read crossing from $FFxx to $00xx changes the high byte, so it pays the cycle too. Every
# example places the operand at the program counter, as if the opcode was just fetched.
#
# Dummy reads (https://www.nesdev.org/6502_cpu.txt, plan 12, decision 4): absolute indexed and "(d),y" read the address
# whose high byte is not fixed yet ("The high byte of the effective address may be invalid at this time, i.e. it may
# be smaller by $100"): read instructions only when the index crosses a page ("+ This cycle will be executed only if
# the effective address was invalid during cycle #4"), write and read-modify-write instructions always ("Because the
# processor cannot undo a write to an invalid address, it always reads from the address first").
RSpec.describe Ruby::Nes::Cpu::AddressingModes do
  describe '#immediate_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus: FlatBus.new, program_counter:) }

    context 'when the program counter is $8000' do
      let(:program_counter) { 0x8000 }

      it 'returns $8000' do
        expect(cpu.immediate_address).to eq(0x8000)
      end

      it 'advances the program counter to $8001' do
        cpu.immediate_address
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the program counter is $FFFF' do
      let(:program_counter) { 0xFFFF }

      it 'returns $FFFF' do
        expect(cpu.immediate_address).to eq(0xFFFF)
      end

      it 'wraps the program counter to $0000' do
        cpu.immediate_address
        expect(cpu.program_counter).to eq(0x0000)
      end
    end
  end

  describe '#zero_page_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000) }

    let(:bus) { FlatBus.new }

    context 'when the operand is $42' do
      before { bus.write(0x8000, 0x42) }

      it 'returns $0042' do
        expect(cpu.zero_page_address).to eq(0x0042)
      end

      it 'advances the program counter past the operand' do
        cpu.zero_page_address
        expect(cpu.program_counter).to eq(0x8001)
      end
    end
  end

  describe '#zero_page_x_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000, index_x:) }

    let(:bus) { FlatBus.new }

    context 'when the operand plus X is $FF' do
      let(:index_x) { 0x0F }

      before { bus.write(0x8000, 0xF0) }

      it 'returns $00FF' do
        expect(cpu.zero_page_x_address).to eq(0x00FF)
      end

      it 'advances the program counter past the operand' do
        cpu.zero_page_x_address
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the operand plus X is $100' do
      let(:index_x) { 0x10 }

      before { bus.write(0x8000, 0xF0) }

      it 'wraps within page zero to $0000' do
        expect(cpu.zero_page_x_address).to eq(0x0000)
      end
    end
  end

  describe '#zero_page_y_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000, index_y:) }

    let(:bus) { FlatBus.new }

    context 'when the operand plus Y is $FF' do
      let(:index_y) { 0x0F }

      before { bus.write(0x8000, 0xF0) }

      it 'returns $00FF' do
        expect(cpu.zero_page_y_address).to eq(0x00FF)
      end

      it 'advances the program counter past the operand' do
        cpu.zero_page_y_address
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the operand plus Y is $100' do
      let(:index_y) { 0x10 }

      before { bus.write(0x8000, 0xF0) }

      it 'wraps within page zero to $0000' do
        expect(cpu.zero_page_y_address).to eq(0x0000)
      end
    end
  end

  describe '#absolute_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000) }

    let(:bus) { FlatBus.new }

    context 'when the operand is $1234' do
      before do
        bus.write(0x8000, 0x34)
        bus.write(0x8001, 0x12)
      end

      it 'returns $1234' do
        expect(cpu.absolute_address).to eq(0x1234)
      end

      it 'advances the program counter past the operand' do
        cpu.absolute_address
        expect(cpu.program_counter).to eq(0x8002)
      end
    end
  end

  describe '#absolute_x_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000, index_x: 0x01) }

    let(:bus) { FlatBus.new }

    context 'when the base plus X stays in the page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFE)
        bus.write(0x8001, 0x12)
      end

      it 'returns $12FF' do
        expect(cpu.absolute_x_address).to eq(0x12FF)
      end

      it 'advances the program counter past the operand' do
        cpu.absolute_x_address
        expect(cpu.program_counter).to eq(0x8002)
      end

      it 'makes a dummy read at $12FF' do
        cpu.absolute_x_address
        expect(bus).to have_received(:read).with(0x12FF).once
      end
    end

    context 'when the base plus X crosses into the next page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFF)
        bus.write(0x8001, 0x12)
      end

      it 'returns $1300' do
        expect(cpu.absolute_x_address).to eq(0x1300)
      end

      it 'adds no cycle' do
        expect { cpu.absolute_x_address }.not_to change(cpu, :cycles)
      end

      it 'makes a dummy read at $1200' do
        cpu.absolute_x_address
        expect(bus).to have_received(:read).with(0x1200).once
      end
    end

    context 'when the base plus X passes $FFFF' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFF)
        bus.write(0x8001, 0xFF)
      end

      it 'wraps to $0000' do
        expect(cpu.absolute_x_address).to eq(0x0000)
      end

      it 'makes a dummy read at $FF00' do
        cpu.absolute_x_address
        expect(bus).to have_received(:read).with(0xFF00).once
      end
    end
  end

  describe '#absolute_x_address_for_read' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000, index_x: 0x01) }

    let(:bus) { FlatBus.new }

    context 'when the base plus X stays in the page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFE)
        bus.write(0x8001, 0x12)
      end

      it 'returns $12FF' do
        expect(cpu.absolute_x_address_for_read).to eq(0x12FF)
      end

      it 'adds no cycle' do
        expect { cpu.absolute_x_address_for_read }.not_to change(cpu, :cycles)
      end

      it 'advances the program counter past the operand' do
        cpu.absolute_x_address_for_read
        expect(cpu.program_counter).to eq(0x8002)
      end

      it 'makes no dummy read' do
        cpu.absolute_x_address_for_read
        expect(bus).not_to have_received(:read).with(0x12FF)
      end
    end

    context 'when the base plus X crosses into the next page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFF)
        bus.write(0x8001, 0x12)
      end

      it 'returns $1300' do
        expect(cpu.absolute_x_address_for_read).to eq(0x1300)
      end

      it 'adds one cycle' do
        expect { cpu.absolute_x_address_for_read }.to change(cpu, :cycles).by(1)
      end

      it 'makes a dummy read at $1200' do
        cpu.absolute_x_address_for_read
        expect(bus).to have_received(:read).with(0x1200).once
      end
    end

    context 'when the base plus X passes $FFFF' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFF)
        bus.write(0x8001, 0xFF)
      end

      it 'wraps to $0000' do
        expect(cpu.absolute_x_address_for_read).to eq(0x0000)
      end

      it 'adds one cycle' do
        expect { cpu.absolute_x_address_for_read }.to change(cpu, :cycles).by(1)
      end

      it 'makes a dummy read at $FF00' do
        cpu.absolute_x_address_for_read
        expect(bus).to have_received(:read).with(0xFF00).once
      end
    end
  end

  describe '#absolute_y_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000, index_y: 0x01) }

    let(:bus) { FlatBus.new }

    context 'when the base plus Y stays in the page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFE)
        bus.write(0x8001, 0x12)
      end

      it 'returns $12FF' do
        expect(cpu.absolute_y_address).to eq(0x12FF)
      end

      it 'advances the program counter past the operand' do
        cpu.absolute_y_address
        expect(cpu.program_counter).to eq(0x8002)
      end

      it 'makes a dummy read at $12FF' do
        cpu.absolute_y_address
        expect(bus).to have_received(:read).with(0x12FF).once
      end
    end

    context 'when the base plus Y crosses into the next page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFF)
        bus.write(0x8001, 0x12)
      end

      it 'returns $1300' do
        expect(cpu.absolute_y_address).to eq(0x1300)
      end

      it 'adds no cycle' do
        expect { cpu.absolute_y_address }.not_to change(cpu, :cycles)
      end

      it 'makes a dummy read at $1200' do
        cpu.absolute_y_address
        expect(bus).to have_received(:read).with(0x1200).once
      end
    end

    context 'when the base plus Y passes $FFFF' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFF)
        bus.write(0x8001, 0xFF)
      end

      it 'wraps to $0000' do
        expect(cpu.absolute_y_address).to eq(0x0000)
      end

      it 'makes a dummy read at $FF00' do
        cpu.absolute_y_address
        expect(bus).to have_received(:read).with(0xFF00).once
      end
    end
  end

  describe '#absolute_y_address_for_read' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000, index_y: 0x01) }

    let(:bus) { FlatBus.new }

    context 'when the base plus Y stays in the page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFE)
        bus.write(0x8001, 0x12)
      end

      it 'returns $12FF' do
        expect(cpu.absolute_y_address_for_read).to eq(0x12FF)
      end

      it 'adds no cycle' do
        expect { cpu.absolute_y_address_for_read }.not_to change(cpu, :cycles)
      end

      it 'advances the program counter past the operand' do
        cpu.absolute_y_address_for_read
        expect(cpu.program_counter).to eq(0x8002)
      end

      it 'makes no dummy read' do
        cpu.absolute_y_address_for_read
        expect(bus).not_to have_received(:read).with(0x12FF)
      end
    end

    context 'when the base plus Y crosses into the next page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFF)
        bus.write(0x8001, 0x12)
      end

      it 'returns $1300' do
        expect(cpu.absolute_y_address_for_read).to eq(0x1300)
      end

      it 'adds one cycle' do
        expect { cpu.absolute_y_address_for_read }.to change(cpu, :cycles).by(1)
      end

      it 'makes a dummy read at $1200' do
        cpu.absolute_y_address_for_read
        expect(bus).to have_received(:read).with(0x1200).once
      end
    end

    context 'when the base plus Y passes $FFFF' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0xFF)
        bus.write(0x8001, 0xFF)
      end

      it 'wraps to $0000' do
        expect(cpu.absolute_y_address_for_read).to eq(0x0000)
      end

      it 'adds one cycle' do
        expect { cpu.absolute_y_address_for_read }.to change(cpu, :cycles).by(1)
      end

      it 'makes a dummy read at $FF00' do
        cpu.absolute_y_address_for_read
        expect(bus).to have_received(:read).with(0xFF00).once
      end
    end
  end

  describe '#indirect_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000) }

    let(:bus) { FlatBus.new }

    context 'when the pointer is $1234' do
      before do
        bus.write(0x8000, 0x34)
        bus.write(0x8001, 0x12)
        bus.write(0x1234, 0xCD)
        bus.write(0x1235, 0xAB)
      end

      it 'returns the address stored at $1234 and $1235' do
        expect(cpu.indirect_address).to eq(0xABCD)
      end

      it 'advances the program counter past the operand' do
        cpu.indirect_address
        expect(cpu.program_counter).to eq(0x8002)
      end
    end

    context 'when the pointer is $10FF' do
      before do
        bus.write(0x8000, 0xFF)
        bus.write(0x8001, 0x10)
        bus.write(0x10FF, 0xCD)
        bus.write(0x1000, 0xAB)
        bus.write(0x1100, 0xEE)
      end

      it 'reads the high byte from $1000, not $1100' do
        expect(cpu.indirect_address).to eq(0xABCD)
      end
    end
  end

  describe '#indexed_indirect_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000, index_x:) }

    let(:bus) { FlatBus.new }

    context 'when the operand plus X stays in page zero' do
      let(:index_x) { 0x04 }

      before do
        bus.write(0x8000, 0x20)
        bus.write(0x0024, 0x34)
        bus.write(0x0025, 0x12)
      end

      it 'returns the address stored at $0024 and $0025' do
        expect(cpu.indexed_indirect_address).to eq(0x1234)
      end

      it 'advances the program counter past the operand' do
        cpu.indexed_indirect_address
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the operand plus X passes $FF' do
      let(:index_x) { 0x14 }

      before do
        bus.write(0x8000, 0xF0)
        bus.write(0x0004, 0x34)
        bus.write(0x0005, 0x12)
        bus.write(0x0104, 0xEE)
      end

      it 'returns the address stored at $0004 and $0005' do
        expect(cpu.indexed_indirect_address).to eq(0x1234)
      end
    end

    context 'when the pointer is $FF' do
      let(:index_x) { 0x04 }

      before do
        bus.write(0x8000, 0xFB)
        bus.write(0x00FF, 0x34)
        bus.write(0x0000, 0x12)
        bus.write(0x0100, 0xEE)
      end

      it 'reads the high byte from $0000, not $0100' do
        expect(cpu.indexed_indirect_address).to eq(0x1234)
      end
    end
  end

  describe '#indirect_indexed_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000, index_y: 0x01) }

    let(:bus) { FlatBus.new }

    context 'when the pointer is $FF' do
      before do
        bus.write(0x8000, 0xFF)
        bus.write(0x00FF, 0x34)
        bus.write(0x0000, 0x12)
        bus.write(0x0100, 0xEE)
      end

      it 'reads the high byte of the base from $0000, not $0100' do
        expect(cpu.indirect_indexed_address).to eq(0x1235)
      end
    end

    context 'when the base plus Y stays in the page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0x20)
        bus.write(0x0020, 0xFE)
        bus.write(0x0021, 0x12)
      end

      it 'returns $12FF' do
        expect(cpu.indirect_indexed_address).to eq(0x12FF)
      end

      it 'advances the program counter past the operand' do
        cpu.indirect_indexed_address
        expect(cpu.program_counter).to eq(0x8001)
      end

      it 'makes a dummy read at $12FF' do
        cpu.indirect_indexed_address
        expect(bus).to have_received(:read).with(0x12FF).once
      end
    end

    context 'when the base plus Y crosses into the next page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0x20)
        bus.write(0x0020, 0xFF)
        bus.write(0x0021, 0x12)
      end

      it 'returns $1300' do
        expect(cpu.indirect_indexed_address).to eq(0x1300)
      end

      it 'adds no cycle' do
        expect { cpu.indirect_indexed_address }.not_to change(cpu, :cycles)
      end

      it 'makes a dummy read at $1200' do
        cpu.indirect_indexed_address
        expect(bus).to have_received(:read).with(0x1200).once
      end
    end

    context 'when the base plus Y passes $FFFF' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0x20)
        bus.write(0x0020, 0xFF)
        bus.write(0x0021, 0xFF)
      end

      it 'wraps to $0000' do
        expect(cpu.indirect_indexed_address).to eq(0x0000)
      end

      it 'makes a dummy read at $FF00' do
        cpu.indirect_indexed_address
        expect(bus).to have_received(:read).with(0xFF00).once
      end
    end
  end

  describe '#indirect_indexed_address_for_read' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0x8000, index_y: 0x01) }

    let(:bus) { FlatBus.new }

    context 'when the pointer is $FF' do
      before do
        bus.write(0x8000, 0xFF)
        bus.write(0x00FF, 0x34)
        bus.write(0x0000, 0x12)
        bus.write(0x0100, 0xEE)
      end

      it 'reads the high byte of the base from $0000, not $0100' do
        expect(cpu.indirect_indexed_address_for_read).to eq(0x1235)
      end
    end

    context 'when the base plus Y stays in the page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0x20)
        bus.write(0x0020, 0xFE)
        bus.write(0x0021, 0x12)
      end

      it 'returns $12FF' do
        expect(cpu.indirect_indexed_address_for_read).to eq(0x12FF)
      end

      it 'adds no cycle' do
        expect { cpu.indirect_indexed_address_for_read }.not_to change(cpu, :cycles)
      end

      it 'advances the program counter past the operand' do
        cpu.indirect_indexed_address_for_read
        expect(cpu.program_counter).to eq(0x8001)
      end

      it 'makes no dummy read' do
        cpu.indirect_indexed_address_for_read
        expect(bus).not_to have_received(:read).with(0x12FF)
      end
    end

    context 'when the base plus Y crosses into the next page' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0x20)
        bus.write(0x0020, 0xFF)
        bus.write(0x0021, 0x12)
      end

      it 'returns $1300' do
        expect(cpu.indirect_indexed_address_for_read).to eq(0x1300)
      end

      it 'adds one cycle' do
        expect { cpu.indirect_indexed_address_for_read }.to change(cpu, :cycles).by(1)
      end

      it 'makes a dummy read at $1200' do
        cpu.indirect_indexed_address_for_read
        expect(bus).to have_received(:read).with(0x1200).once
      end
    end

    context 'when the base plus Y passes $FFFF' do
      before do
        allow(bus).to receive(:read).and_call_original
        bus.write(0x8000, 0x20)
        bus.write(0x0020, 0xFF)
        bus.write(0x0021, 0xFF)
      end

      it 'wraps to $0000' do
        expect(cpu.indirect_indexed_address_for_read).to eq(0x0000)
      end

      it 'adds one cycle' do
        expect { cpu.indirect_indexed_address_for_read }.to change(cpu, :cycles).by(1)
      end

      it 'makes a dummy read at $FF00' do
        cpu.indirect_indexed_address_for_read
        expect(bus).to have_received(:read).with(0xFF00).once
      end
    end
  end

  describe '#relative_address' do
    subject(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter:) }

    let(:bus) { FlatBus.new }

    context 'when the offset is $7F' do
      let(:program_counter) { 0x8000 }

      before { bus.write(0x8000, 0x7F) }

      it 'returns the byte after the offset plus 127' do
        expect(cpu.relative_address).to eq(0x8080)
      end

      it 'advances the program counter past the offset only' do
        cpu.relative_address
        expect(cpu.program_counter).to eq(0x8001)
      end
    end

    context 'when the offset is $80' do
      let(:program_counter) { 0x8000 }

      before { bus.write(0x8000, 0x80) }

      it 'returns the byte after the offset minus 128' do
        expect(cpu.relative_address).to eq(0x7F81)
      end
    end

    context 'when a forward offset passes $FFFF' do
      let(:program_counter) { 0xFFFE }

      before { bus.write(0xFFFE, 0x10) }

      it 'wraps to $000F' do
        expect(cpu.relative_address).to eq(0x000F)
      end
    end

    context 'when a backward offset passes $0000' do
      let(:program_counter) { 0x0000 }

      before { bus.write(0x0000, 0xF0) }

      it 'wraps to $FFF1' do
        expect(cpu.relative_address).to eq(0xFFF1)
      end
    end
  end
end
