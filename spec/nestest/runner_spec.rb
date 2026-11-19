# frozen_string_literal: true

# nestest's automation mode (https://www.nesdev.org/wiki/Emulator_tests, plan 08): the program counter starts at $C000
# instead of the reset vector, on a powered-up CPU (https://www.nesdev.org/wiki/CPU_power_up_state: P reads $24 when
# pushed, S is $FD, and the reset sequence took 7 cycles). The official opcodes' result is written to $0002 and the
# unofficial opcodes' result to $0003, zero meaning every test passed (other/nestest.txt in the test ROM collection).
# The runner steps a whole console, so the trace's PPU column moves with the CPU (plan 12); a powered-up console
# stands at the reset vector with P $24, S $FD and the PPU 21 dots into scanline 0 after the 7 cycles of reset.
RSpec.describe Nestest::Runner do
  describe '.automation_mode' do
    let(:cartridge) { Cartridges.build }

    it 'starts at $C000 with the power-up state', :aggregate_failures do
      automation_console = described_class.automation_mode(cartridge).console
      expect(automation_console.cpu).to have_attributes(program_counter: 0xC000, cycles: 7)
      expect(automation_console.cpu.stack.pointer).to eq(0xFD)
      expect(automation_console.cpu.status.byte_pushed_by_interrupt).to eq(0x24)
      expect(automation_console.ppu).to have_attributes(scanline: 0, dot: 21)
    end
  end

  describe '#first_divergence' do
    context 'when there are no expected lines' do
      subject(:runner) { described_class.new(console:) }

      let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0xEA, 0xEA])) }

      it 'finds none' do
        expect(runner.first_divergence([])).to be_nil
      end

      it 'runs nothing' do
        expect { runner.first_divergence([]) }.not_to(change { [console.cpu.program_counter, console.cpu.cycles] })
      end
    end

    context 'when there are expected lines' do
      context 'but the first one differs from the trace' do
        subject(:runner) { described_class.new(console:) }

        let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0xEA, 0xEA])) }
        let(:expected_lines) do
          [
            '8000  EA        NOP  A:01 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7',
            '8001  EA        NOP  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 27 CYC:9'
          ]
        end

        it 'reports line 1 with both lines' do
          expect(runner.first_divergence(expected_lines)).to have_attributes(
            line_number: 1,
            expected: '8000  EA        NOP  A:01 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7',
            actual: '8000  EA        NOP  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7'
          )
        end

        it 'runs nothing' do
          expect { runner.first_divergence(expected_lines) }
            .not_to(change { [console.cpu.program_counter, console.cpu.cycles] })
        end
      end

      context 'and the first one matches' do
        context 'but a later one differs' do
          subject(:runner) { described_class.new(console:) }

          let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0xEA, 0xEA, 0xEA])) }
          let(:expected_lines) do
            [
              '8000  EA        NOP  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7',
              '8001  EA        NOP  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 27 CYC:10',
              '8002  EA        NOP  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 33 CYC:11'
            ]
          end

          it 'reports that line with both lines' do
            expect(runner.first_divergence(expected_lines)).to have_attributes(
              line_number: 2,
              expected: '8001  EA        NOP  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 27 CYC:10',
              actual: '8001  EA        NOP  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 27 CYC:9'
            )
          end

          it 'stops before its instruction' do
            runner.first_divergence(expected_lines)
            expect(console.cpu).to have_attributes(program_counter: 0x8001, cycles: 9)
          end
        end

        context 'and every one matches' do
          context 'and they trace a synthetic program' do
            subject(:runner) { described_class.new(console:) }

            let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0xA9, 0x42, 0xEA])) }
            let(:expected_lines) do
              [
                '8000  A9 42     LDA  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7',
                '8002  EA        NOP  A:42 X:00 Y:00 P:24 SP:FD PPU:  0, 27 CYC:9'
              ]
            end

            it 'finds none' do
              expect(runner.first_divergence(expected_lines)).to be_nil
            end

            it "runs the last line's instruction too, the PPU along", :aggregate_failures do
              runner.first_divergence(expected_lines)
              expect(console.cpu).to have_attributes(program_counter: 0x8003, cycles: 11)
              expect(console.ppu).to have_attributes(scanline: 0, dot: 33)
            end
          end

          context "and they are nestest.log's lines", test_rom: [Nestest::ROM_PATH, Nestest::LOG_PATH] do
            subject(:runner) { described_class.automation_mode(cartridge) }

            let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }
            let(:log_lines) { Nestest::Log.lines(File.read(test_rom_path(Nestest::LOG_PATH))) }

            it 'finds none' do
              expect(runner.first_divergence(log_lines)).to be_nil
            end

            # Line 8991 is `C66E RTS` with S at $FD: it pulls $0000 from the bottom of the stack and returns to $0001.
            it "runs the last line's instruction too" do
              runner.first_divergence(log_lines)
              expect(runner.cpu.program_counter).to eq(0x0001)
            end
          end
        end
      end
    end
  end

  describe '#official_result' do
    context 'when $0002 holds an error code' do
      subject(:runner) { described_class.new(console:) }

      let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0xEA])) }

      before { console.cpu_bus.write(0x0002, 0x4E) }

      it 'is that code' do
        expect(runner.official_result).to eq(0x4E)
      end
    end

    context 'when nestest.nes has run its whole log', test_rom: [Nestest::ROM_PATH, Nestest::LOG_PATH] do
      subject(:runner) { described_class.automation_mode(cartridge) }

      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }
      let(:log_lines) { Nestest::Log.lines(File.read(test_rom_path(Nestest::LOG_PATH))) }

      before { runner.first_divergence(log_lines) }

      it 'is $00' do
        expect(runner.official_result).to eq(0x00)
      end
    end
  end

  describe '#unofficial_result' do
    context 'when $0003 holds an error code' do
      subject(:runner) { described_class.new(console:) }

      let(:console) { Ruby::Nes::Console.new(Cartridges.with_program([0xEA])) }

      before { console.cpu_bus.write(0x0003, 0x4E) }

      it 'is that code' do
        expect(runner.unofficial_result).to eq(0x4E)
      end
    end

    context 'when nestest.nes has run its whole log', test_rom: [Nestest::ROM_PATH, Nestest::LOG_PATH] do
      subject(:runner) { described_class.automation_mode(cartridge) }

      let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }
      let(:log_lines) { Nestest::Log.lines(File.read(test_rom_path(Nestest::LOG_PATH))) }

      before { runner.first_divergence(log_lines) }

      it 'is $00' do
        expect(runner.unofficial_result).to eq(0x00)
      end
    end
  end
end
