# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

# A pass is nestest in automation mode (plan 08) from a fresh console, for the 8991 instructions of nestest.log. Its
# last line is `C66E RTS` at CYC:26554; RTS takes 6 cycles (https://www.nesdev.org/wiki/Instruction_reference#RTS)
# and the run starts at CYC:7 after the reset, so a pass emulates 26554 + 6 - 7 = 26553 cycles. nestest writes its
# results to $0002 (official opcodes) and $0003 (unofficial opcodes), zero meaning every test passed
# (other/nestest.txt in the test ROM collection).
RSpec.describe CpuBenchmark::Workload do
  describe '#run' do
    context 'when no cycles are asked' do
      subject(:workload) { described_class.new(cartridge, steps_per_pass: 3) }

      let(:cartridge) { Cartridges.build }

      it 'runs no pass' do
        expect(workload.run(cycles: 0)).to eq(CpuBenchmark::Sample.new(cycles: 0, seconds: 0.0))
      end
    end

    context 'when cycles are asked' do
      context "but a pass leaves nestest's official result failed" do
        subject(:workload) { described_class.new(cartridge, steps_per_pass: 3) }

        # $C000: LDA #$01; STA $02; JMP $C004 (the JMP loops on itself).
        let(:program) { [0xA9, 0x01, 0x85, 0x02, 0x4C, 0x04, 0xC0] }
        let(:cartridge) { Cartridges.build(prg_rom: program + Array.new(16_384 - program.size, 0xEA)) }

        it 'raises BrokenVariant naming both result bytes' do
          expect { workload.run(cycles: 1) }
            .to raise_error(CpuBenchmark::BrokenVariant, 'nestest failed after a pass: $0002 = $01, $0003 = $00')
        end
      end

      context "but a pass leaves nestest's unofficial result failed" do
        subject(:workload) { described_class.new(cartridge, steps_per_pass: 3) }

        # $C000: LDA #$01; STA $03; JMP $C004 (the JMP loops on itself).
        let(:program) { [0xA9, 0x01, 0x85, 0x03, 0x4C, 0x04, 0xC0] }
        let(:cartridge) { Cartridges.build(prg_rom: program + Array.new(16_384 - program.size, 0xEA)) }

        it 'raises BrokenVariant naming both result bytes' do
          expect { workload.run(cycles: 1) }
            .to raise_error(CpuBenchmark::BrokenVariant, 'nestest failed after a pass: $0002 = $00, $0003 = $01')
        end
      end

      context 'and every pass leaves both results passed', test_rom: [Nestest::ROM_PATH] do
        context 'and they are fewer than one pass' do
          subject(:workload) { described_class.new(cartridge, steps_per_pass: 8991) }

          let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }

          it 'runs one whole pass' do
            expect(workload.run(cycles: 1).cycles).to eq(26_553)
          end
        end

        context 'and they are exactly one pass' do
          subject(:workload) { described_class.new(cartridge, steps_per_pass: 8991) }

          let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }

          it 'runs one pass' do
            expect(workload.run(cycles: 26_553).cycles).to eq(26_553)
          end
        end

        # A CPU reused after a pass would go on at $0001, where its last RTS returns, and leave the results failed or
        # the cycles different.
        context 'and they exceed one pass by one cycle' do
          subject(:workload) { described_class.new(cartridge, steps_per_pass: 8991, clock:) }

          let(:cartridge) { Ruby::Nes::Cartridge::Loader.from_file(test_rom_path(Nestest::ROM_PATH)) }
          # The clock is read around each pass's instructions only: 1 and 2 seconds, with 8 seconds between them
          # (building the second console) that must not count.
          let(:clock) { [0.0, 1.0, 9.0, 11.0].each.method(:next) }

          it 'runs two whole passes, timing only their instructions' do
            expect(workload.run(cycles: 26_554)).to eq(CpuBenchmark::Sample.new(cycles: 53_106, seconds: 3.0))
          end
        end
      end
    end
  end
end
