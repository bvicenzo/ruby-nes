# frozen_string_literal: true

# The tracer follows nestest.log's columns up to the mnemonic, then shows the machine state only (plan 08, decision 5),
# with nestest's PPU column, the scanline and dot right-aligned in three characters ("PPU:  0, 21", plan 12). P is the
# byte an interrupt would push, bit 5 set and B clear: debuggers have "no convention" for those two bits
# (https://www.nesdev.org/wiki/Status_flags), so the tracer follows nestest (P:24 after power-up). Every CPU below is
# reset through a vector pointing at $C000 or $FFFE (7 cycles, S three bytes lower) and then has its flags restored to
# N and C ($81), so P reads $A1.
#
# An interrupt is a step of its own (decision 14 of docs/architecture.md), so when the next step takes one the line
# names it instead of the instruction; a jammed CPU, halted "until reset" (plan 09), shows the halt (plan 12).
RSpec.describe Ruby::Nes::Debug::Tracer do
  describe '#line' do
    subject(:tracer) { described_class.new(cpu:, bus:, ppu:) }

    let(:bus) { FlatBus.new }
    let(:ppu) { instance_double(Ruby::Nes::Ppu, scanline: 241, dot: 5) }

    before do
      bus.write_bytes(Ruby::Nes::Cpu::RESET_VECTOR, reset_vector)
      cpu.reset
      cpu.status.restore(0x81)
    end

    context 'when the CPU is jammed' do
      let(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator: 0x0A, index_x: 0xB1, index_y: 0x2C, stack_pointer: 0x40) }
      let(:reset_vector) { [0x00, 0xC0] }

      before do
        bus.write_bytes(0xC000, [0x02])
        cpu.step
      end

      it 'shows the halt at the program counter, with the machine state' do
        expect(tracer.line).to eq('C001  JAMMED         A:0A X:B1 Y:2C P:A1 SP:3D PPU:241,  5 CYC:9')
      end
    end

    context 'when the next step takes an interrupt' do
      context 'and it is an NMI' do
        let(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator: 0x0A, index_x: 0xB1, index_y: 0x2C, stack_pointer: 0x40) }
        let(:reset_vector) { [0x00, 0xC0] }

        before do
          bus.write_bytes(0xC000, [0xEA])
          cpu.nmi_line_changed(true, 0)
        end

        it 'names the NMI instead of the instruction, with the machine state' do
          expect(tracer.line).to eq('C000  NMI            A:0A X:B1 Y:2C P:A1 SP:3D PPU:241,  5 CYC:7')
        end
      end

      context 'and it is an IRQ' do
        let(:cpu) do
          Ruby::Nes::Cpu.new(bus:, accumulator: 0x0A, index_x: 0xB1, index_y: 0x2C, stack_pointer: 0x40).tap do |cpu|
            cpu.assert_irq(Ruby::Nes::Cpu::InterruptLines::MAPPER_IRQ)
          end
        end
        let(:reset_vector) { [0x00, 0xC0] }

        before { bus.write_bytes(0xC000, [0xEA]) }

        it 'names the IRQ instead of the instruction, with the machine state' do
          expect(tracer.line).to eq('C000  IRQ            A:0A X:B1 Y:2C P:A1 SP:3D PPU:241,  5 CYC:7')
        end
      end
    end

    context 'when the next step runs an instruction' do
      let(:cpu) { Ruby::Nes::Cpu.new(bus:, accumulator: 0x0A, index_x: 0xB1, index_y: 0x2C, stack_pointer: 0x40) }

      # nestest.log marks an unofficial opcode with `*` in the column before the mnemonic: "C6BD  04 A9    *NOP".
      context 'and the opcode at the program counter is unofficial' do
        let(:reset_vector) { [0x00, 0xC0] }

        before { bus.write_bytes(0xC000, [0xA7, 0x42, 0x12]) }

        it 'marks its mnemonic with *' do
          expect(tracer.line).to eq('C000  A7 42    *LAX  A:0A X:B1 Y:2C P:A1 SP:3D PPU:241,  5 CYC:7')
        end
      end

      context 'and the opcode is official' do
        context 'and the instruction is one byte' do
          let(:reset_vector) { [0x00, 0xC0] }

          before { bus.write_bytes(0xC000, [0xEA, 0x34, 0x12]) }

          it 'shows the opcode byte padded to the bytes column' do
            expect(tracer.line).to eq('C000  EA        NOP  A:0A X:B1 Y:2C P:A1 SP:3D PPU:241,  5 CYC:7')
          end
        end

        context 'and the instruction is two bytes' do
          let(:reset_vector) { [0x00, 0xC0] }

          before { bus.write_bytes(0xC000, [0xA9, 0x42, 0x12]) }

          it 'shows the opcode and its operand' do
            expect(tracer.line).to eq('C000  A9 42     LDA  A:0A X:B1 Y:2C P:A1 SP:3D PPU:241,  5 CYC:7')
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
              expect(tracer.line).to eq('FFFE  AD 34 12  LDA  A:0A X:B1 Y:2C P:A1 SP:3D PPU:241,  5 CYC:7')
            end
          end

          context 'and it ends below $FFFF' do
            let(:reset_vector) { [0x00, 0xC0] }

            before do
              bus.write_bytes(0xC000, [0x4C, 0x34, 0x12])
              allow(bus).to receive(:read).and_call_original
            end

            it 'shows the opcode and both operand bytes' do
              expect(tracer.line).to eq('C000  4C 34 12  JMP  A:0A X:B1 Y:2C P:A1 SP:3D PPU:241,  5 CYC:7')
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
end
