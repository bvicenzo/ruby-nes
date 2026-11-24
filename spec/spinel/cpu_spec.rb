# frozen_string_literal: true

require 'json'
require 'open3'
require 'tempfile'

RSpec.describe 'spinel/cpu.rb', test_rom: [Nestest::ROM_PATH, Nestest::LOG_PATH] do
  # The program as CRuby runs it, with no JIT (none inherited from the environment) and a workload of one pass (plan 26,
  # decision 6).
  describe 'a run' do
    let(:no_inherited_jit) { { 'RUBYOPT' => nil, 'RUBY_YJIT_ENABLE' => nil, 'RUBY_ZJIT_ENABLE' => nil } }
    let(:script) { File.expand_path('../../spinel/cpu.rb', __dir__) }

    context 'when it is not given five arguments' do
      it 'stops with the usage, printing no measurement' do
        output, errors, status = Open3.capture3(no_inherited_jit, RbConfig.ruby, script, test_rom_path(Nestest::ROM_PATH))

        expect([status.success?, output, errors]).to match([false, '', start_with('Usage: spinel/cpu.rb')])
      end
    end

    context 'when it is given five arguments' do
      let(:command) { [RbConfig.ruby, script, test_rom_path(Nestest::ROM_PATH), log_path, '1', '0', '1'] }

      context 'but the trace diverges from the log' do
        let(:diverging_log) do
          log_lines = File.readlines(test_rom_path(Nestest::LOG_PATH))
          Tempfile.create(['nestest', '.log']).tap do |file|
            file.write(log_lines.first.sub('A:00', 'A:FF'), *log_lines.drop(1))
            file.close
          end
        end
        let(:log_path) { diverging_log.path }

        after { File.delete(log_path) }

        it 'stops with the divergence, printing no measurement' do
          output, errors, status = Open3.capture3(no_inherited_jit, *command)

          expect([status.success?, output, errors]).to match([false, '', start_with('nestest.log line 1 differs')])
        end
      end

      context 'and the trace matches the log' do
        let(:log_path) { test_rom_path(Nestest::LOG_PATH) }

        it 'prints the baseline measurement as one JSON line' do
          output, status = Open3.capture2(no_inherited_jit, *command)

          expect([status.success?, JSON.parse(output, symbolize_names: true)]).to match(
            [
              true,
              {
                configuration: 'interpreter',
                variant: 'baseline',
                megahertz: be_positive,
                percent_of_real_time: be_positive,
                spread: 0.0,
                ruby: start_with("ruby #{RUBY_VERSION}")
              }
            ]
          )
        end
      end
    end
  end
end
