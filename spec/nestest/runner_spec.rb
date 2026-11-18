# frozen_string_literal: true

# nestest's automation mode (https://www.nesdev.org/wiki/Emulator_tests, plan 08): the program counter starts at $C000
# instead of the reset vector, on a powered-up CPU (https://www.nesdev.org/wiki/CPU_power_up_state: P reads $24 when
# pushed, S is $FD, and the reset sequence took 7 cycles). The official opcodes' result is written to $0002, zero
# meaning every test passed (other/nestest.txt in the test ROM collection).
RSpec.describe Nestest::Runner do
  describe '.automation_mode' do
    let(:cartridge) { Cartridges.build }

    it 'starts at $C000 with the power-up state', :aggregate_failures do
      automation_cpu = described_class.automation_mode(cartridge).cpu
      expect(automation_cpu).to have_attributes(program_counter: 0xC000, cycles: 7)
      expect(automation_cpu.stack.pointer).to eq(0xFD)
      expect(automation_cpu.status.byte_pushed_by_interrupt).to eq(0x24)
    end
  end

  describe '#first_divergence' do
    context 'when there are no expected lines' do
      subject(:runner) { described_class.new(cpu:, bus:) }

      let(:bus) { FlatBus.new }
      let(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0xC000) }

      before { bus.write_bytes(0xC000, [0xEA, 0xEA]) }

      it 'finds none' do
        expect(runner.first_divergence([])).to be_nil
      end

      it 'runs nothing' do
        expect { runner.first_divergence([]) }.not_to(change { [cpu.program_counter, cpu.cycles] })
      end
    end

    context 'when there are expected lines' do
      context 'but the first one differs from the trace' do
        subject(:runner) { described_class.new(cpu:, bus:) }

        let(:bus) { FlatBus.new }
        let(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0xC000) }
        let(:expected_lines) do
          [
            'C000  EA        NOP  A:01 X:00 Y:00 P:20 SP:00 CYC:0',
            'C001  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:2'
          ]
        end

        before { bus.write_bytes(0xC000, [0xEA, 0xEA]) }

        it 'reports line 1 with both lines' do
          expect(runner.first_divergence(expected_lines)).to have_attributes(
            line_number: 1,
            expected: 'C000  EA        NOP  A:01 X:00 Y:00 P:20 SP:00 CYC:0',
            actual: 'C000  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:0'
          )
        end

        it 'runs nothing' do
          expect { runner.first_divergence(expected_lines) }.not_to(change { [cpu.program_counter, cpu.cycles] })
        end
      end

      context 'and the first one matches' do
        context 'but a later one differs' do
          subject(:runner) { described_class.new(cpu:, bus:) }

          let(:bus) { FlatBus.new }
          let(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0xC000) }
          let(:expected_lines) do
            [
              'C000  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:0',
              'C001  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:3',
              'C002  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:4'
            ]
          end

          before { bus.write_bytes(0xC000, [0xEA, 0xEA, 0xEA]) }

          it 'reports that line with both lines' do
            expect(runner.first_divergence(expected_lines)).to have_attributes(
              line_number: 2,
              expected: 'C001  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:3',
              actual: 'C001  EA        NOP  A:00 X:00 Y:00 P:20 SP:00 CYC:2'
            )
          end

          it 'stops before its instruction' do
            runner.first_divergence(expected_lines)
            expect(cpu).to have_attributes(program_counter: 0xC001, cycles: 2)
          end
        end

        context 'and every one matches' do
          context 'and they trace a synthetic program' do
            subject(:runner) { described_class.new(cpu:, bus:) }

            let(:bus) { FlatBus.new }
            let(:cpu) { Ruby::Nes::Cpu.new(bus:, program_counter: 0xC000) }
            let(:expected_lines) do
              [
                'C000  A9 42     LDA  A:00 X:00 Y:00 P:20 SP:00 CYC:0',
                'C002  EA        NOP  A:42 X:00 Y:00 P:20 SP:00 CYC:2'
              ]
            end

            before { bus.write_bytes(0xC000, [0xA9, 0x42, 0xEA]) }

            it 'finds none' do
              expect(runner.first_divergence(expected_lines)).to be_nil
            end

            it "runs the last line's instruction too" do
              runner.first_divergence(expected_lines)
              expect(cpu).to have_attributes(program_counter: 0xC003, cycles: 4)
            end
          end

          context "and they are nestest.log's official section", test_rom: [Nestest::ROM_PATH, Nestest::LOG_PATH] do
            subject(:runner) { described_class.automation_mode(cartridge) }

            let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }
            let(:official_lines) { Nestest::Log.official_lines(File.read(test_rom_path(Nestest::LOG_PATH))) }

            it 'finds none' do
              expect(runner.first_divergence(official_lines)).to be_nil
            end

            # Line 5003 is `C6BC PLP`; the first unofficial opcode follows at $C6BD.
            it "runs the last line's instruction too" do
              runner.first_divergence(official_lines)
              expect(runner.cpu.program_counter).to eq(0xC6BD)
            end
          end
        end
      end
    end
  end

  describe '#official_result' do
    context 'when $0002 holds an error code' do
      subject(:runner) { described_class.new(cpu:, bus:) }

      let(:bus) { FlatBus.new }
      let(:cpu) { Ruby::Nes::Cpu.new(bus:) }

      before { bus.write(0x0002, 0x4E) }

      it 'is that code' do
        expect(runner.official_result).to eq(0x4E)
      end
    end

    context 'when nestest.nes has run its official section', test_rom: [Nestest::ROM_PATH, Nestest::LOG_PATH] do
      subject(:runner) { described_class.automation_mode(cartridge) }

      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }
      let(:official_lines) { Nestest::Log.official_lines(File.read(test_rom_path(Nestest::LOG_PATH))) }

      before { runner.first_divergence(official_lines) }

      it 'is $00' do
        expect(runner.official_result).to eq(0x00)
      end
    end
  end
end
