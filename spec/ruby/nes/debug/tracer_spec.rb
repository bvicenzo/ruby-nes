# frozen_string_literal: true

# The tracer follows nestest.log's columns up to the mnemonic, then shows the machine state only (plan 08, decision 5).
# P is the byte an interrupt would push, bit 5 set and B clear: debuggers have "no convention" for those two bits
# (https://www.nesdev.org/wiki/Status_flags), so the tracer follows nestest (P:24 after power-up). Every CPU below is
# reset through a vector pointing at the instruction (7 cycles, S three bytes lower) and then has its flags restored to
# N, I and C ($85), so P reads $A5.
RSpec.describe Ruby::Nes::Debug::Tracer do
  describe '#line' do
    subject(:tracer) { described_class.new(cpu:, bus:) }

    let(:bus) { FlatBus.new }
    let(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator: 0x0A, index_x: 0xB1, index_y: 0x2C, stack_pointer: 0x40) }

    before do
      bus.write_bytes(Ruby::Nes::Cpu::RESET_VECTOR, reset_vector)
      cpu.reset
      cpu.status.restore(0x85)
    end

    context 'when the opcode at the program counter has no table entry' do
      let(:reset_vector) { [0x00, 0xC0] }

      before { bus.write_bytes(0xC000, [0x02, 0x34, 0x12]) }

      it 'shows the opcode byte alone, with ??? as the mnemonic' do
        expect(tracer.line).to eq('C000  02        ???  A:0A X:B1 Y:2C P:A5 SP:3D CYC:7')
      end
    end

    context 'when the opcode has a table entry' do
      context 'and the instruction is one byte' do
        let(:reset_vector) { [0x00, 0xC0] }

        before { bus.write_bytes(0xC000, [0xEA, 0x34, 0x12]) }

        it 'shows the opcode byte padded to the bytes column' do
          expect(tracer.line).to eq('C000  EA        NOP  A:0A X:B1 Y:2C P:A5 SP:3D CYC:7')
        end
      end

      context 'and the instruction is two bytes' do
        let(:reset_vector) { [0x00, 0xC0] }

        before { bus.write_bytes(0xC000, [0xA9, 0x42, 0x12]) }

        it 'shows the opcode and its operand' do
          expect(tracer.line).to eq('C000  A9 42     LDA  A:0A X:B1 Y:2C P:A5 SP:3D CYC:7')
        end
      end

      context 'and the instruction is three bytes' do
        context 'but it starts at $FFFE' do
          let(:reset_vector) { [0xFE, 0xFF] }

          before do
            bus.write_bytes(0xFFFE, [0xAD, 0x34])
            bus.write(0x0000, 0x12)
          end

          it 'reads its last byte from $0000' do
            expect(tracer.line).to eq('FFFE  AD 34 12  LDA  A:0A X:B1 Y:2C P:A5 SP:3D CYC:7')
          end
        end

        context 'and it ends below $FFFF' do
          let(:reset_vector) { [0x00, 0xC0] }

          before do
            bus.write_bytes(0xC000, [0x4C, 0x34, 0x12])
            allow(bus).to receive(:read).and_call_original
          end

          it 'shows the opcode and both operand bytes' do
            expect(tracer.line).to eq('C000  4C 34 12  JMP  A:0A X:B1 Y:2C P:A5 SP:3D CYC:7')
          end

          # Decision 2: the tracer reads only the bytes the CPU fetches next, each once, through the bus's own read.
          it 'reads each of its bytes once', :aggregate_failures do
            tracer.line
            expect(bus).to have_received(:read).with(0xC000).once
            expect(bus).to have_received(:read).with(0xC001).once
            expect(bus).to have_received(:read).with(0xC002).once
          end

          it 'leaves the CPU unchanged' do
            expect { tracer.line }.not_to(change { [cpu.program_counter, cpu.cycles, cpu.stack.pointer] })
          end
        end
      end
    end
  end
end
