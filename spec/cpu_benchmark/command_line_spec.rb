# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

require 'json'
require 'open3'
require 'stringio'
require 'tempfile'

# Before measuring, the variant's trace is compared with the whole of nestest.log (plan 08's Nestest::Runner): nestest's
# result bytes alone let a broken CPU through. The variants reopen core classes, so each runs in a `ruby bench/cpu.rb`
# process of its own (plan 10, decision 3) on the smallest workload: one nestest pass.
RSpec.describe CpuBenchmark::CommandLine do
  describe '#run' do
    context 'when the variant is unknown' do
      subject(:command_line) { described_class.new(%w[--variant memory_hash], output: StringIO.new) }

      it 'raises UnknownVariant' do
        expect { command_line.run }.to raise_error(CpuBenchmark::UnknownVariant, /memory_hash/)
      end
    end

    context 'when the variant is known' do
      context 'but nestest is unavailable' do
        subject(:command_line) { described_class.new([], output: StringIO.new, requirement:) }

        let(:requirement) { instance_double(TestRoms::Requirement, skip_reason: 'run `rake test_roms:fetch`') }

        it 'raises MissingRom with the reason to fetch it' do
          expect { command_line.run }.to raise_error(CpuBenchmark::MissingRom, 'run `rake test_roms:fetch`')
        end
      end

      context 'and nestest is available', test_rom: [Nestest::ROM_PATH, Nestest::LOG_PATH] do
        context "but the variant's trace diverges from nestest.log" do
          subject(:command_line) { described_class.new([], output: StringIO.new, requirement:) }

          let(:requirement) { instance_double(TestRoms::Requirement, skip_reason: nil) }
          # nestest.log's first line with A:01 instead of A:00.
          let(:diverging_log) do
            Tempfile.create('nestest.log').tap do |log|
              log.write("C000  4C F5 C5  JMP $C5F5                       A:01 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7\n")
              log.close
            end
          end

          before do
            allow(requirement).to receive(:path_of).with(Nestest::ROM_PATH).and_return(test_rom_path(Nestest::ROM_PATH))
            allow(requirement).to receive(:path_of).with(Nestest::LOG_PATH).and_return(diverging_log.path)
          end

          after { File.delete(diverging_log.path) }

          it 'raises BrokenVariant with the divergence' do
            expect { command_line.run }.to raise_error(CpuBenchmark::BrokenVariant, /nestest.log line 1 differs/)
          end
        end

        context "and the variant's trace matches nestest.log" do
          context 'and the variant is the baseline' do
            subject(:command_line) { described_class.new(arguments, output:) }

            let(:arguments) { %w[--cycles 1 --warm-up-runs 0 --runs 1] }
            let(:output) { StringIO.new }

            it 'prints its measurement as one JSON line' do
              command_line.run
              expect(JSON.parse(output.string, symbolize_names: true)).to include(
                configuration: CpuBenchmark::Configuration.current,
                variant: 'baseline',
                megahertz: be_positive,
                percent_of_real_time: be_positive,
                spread: 0.0,
                ruby: RUBY_DESCRIPTION
              )
            end
          end

          context 'and the variant is dispatch_lambda_table' do
            let(:script) { File.expand_path('../../bench/cpu.rb', __dir__) }
            let(:arguments) { %w[--variant dispatch_lambda_table --cycles 1 --warm-up-runs 0 --runs 1] }

            it 'prints its measurement' do
              output, = Open3.capture2e(RbConfig.ruby, script, *arguments)
              expect(output).to include('"variant":"dispatch_lambda_table"')
            end
          end

          context 'and the variant is memory_string' do
            let(:script) { File.expand_path('../../bench/cpu.rb', __dir__) }
            let(:arguments) { %w[--variant memory_string --cycles 1 --warm-up-runs 0 --runs 1] }

            it 'prints its measurement' do
              output, = Open3.capture2e(RbConfig.ruby, script, *arguments)
              expect(output).to include('"variant":"memory_string"')
            end
          end

          context 'and the variant is memory_io_buffer' do
            let(:script) { File.expand_path('../../bench/cpu.rb', __dir__) }
            let(:arguments) { %w[--variant memory_io_buffer --cycles 1 --warm-up-runs 0 --runs 1] }

            it 'prints its measurement' do
              output, = Open3.capture2e(RbConfig.ruby, script, *arguments)
              expect(output).to include('"variant":"memory_io_buffer"')
            end
          end

          context 'and the variant is bits_helpers' do
            let(:script) { File.expand_path('../../bench/cpu.rb', __dir__) }
            let(:arguments) { %w[--variant bits_helpers --cycles 1 --warm-up-runs 0 --runs 1] }

            it 'prints its measurement' do
              output, = Open3.capture2e(RbConfig.ruby, script, *arguments)
              expect(output).to include('"variant":"bits_helpers"')
            end
          end

          context 'and the variant is interrupt_poll_inline' do
            let(:script) { File.expand_path('../../bench/cpu.rb', __dir__) }
            let(:arguments) { %w[--variant interrupt_poll_inline --cycles 1 --warm-up-runs 0 --runs 1] }

            it 'prints its measurement' do
              output, = Open3.capture2e(RbConfig.ruby, script, *arguments)
              expect(output).to include('"variant":"interrupt_poll_inline"')
            end
          end
        end
      end
    end
  end
end
