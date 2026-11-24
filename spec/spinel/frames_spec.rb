# frozen_string_literal: true

require 'json'
require 'open3'
require 'tempfile'
require_relative '../../bench/frame_benchmark'

RSpec.describe 'spinel/frames.rb', test_rom: [Nestest::ROM_PATH] do
  # The program as CRuby runs it, with no JIT (none inherited from the environment; plan 26, decision 6), on nestest, a
  # ROM the test ROM harness provides.
  describe 'a run' do
    let(:no_inherited_jit) { { 'RUBYOPT' => nil, 'RUBY_YJIT_ENABLE' => nil, 'RUBY_ZJIT_ENABLE' => nil } }
    let(:script) { File.expand_path('../../spinel/frames.rb', __dir__) }

    context 'when it is not given five arguments' do
      it 'stops with the usage, printing no measurement' do
        output, errors, status = Open3.capture3(no_inherited_jit, RbConfig.ruby, script, test_rom_path(Nestest::ROM_PATH))

        expect([status.success?, output, errors]).to match([false, '', start_with('Usage: spinel/frames.rb')])
      end
    end

    context 'when it is given five arguments' do
      let(:input_script) do
        Tempfile.create(['input', '.yml']).tap do |file|
          file.write("1: [start]\n")
          file.close
        end
      end
      let(:command) { [RbConfig.ruby, script, test_rom_path(Nestest::ROM_PATH), input_script.path, '1', '1', '2'] }
      # The same three frames played in this process, by the workload the program drives.
      let(:played_workload) do
        rom = test_rom_path(Nestest::ROM_PATH)
        FrameBenchmark::Workload.from_files(rom:, input: input_script.path).tap { |workload| workload.run(frames: 3) }
      end

      after { File.delete(input_script.path) }

      it 'prints the measurement with the digests of the frames played' do
        output, status = Open3.capture2(no_inherited_jit, *command)

        expect([status.success?, JSON.parse(output, symbolize_names: true)]).to match(
          [
            true,
            {
              configuration: 'interpreter',
              frames_per_second: be_positive,
              milliseconds_per_frame: be_positive,
              percent_of_real_time: be_positive,
              spread: be >= 0,
              frame_digest: played_workload.frame_digest,
              audio_digest: played_workload.audio_digest,
              ruby: start_with("ruby #{RUBY_VERSION}")
            }
          ]
        )
      end
    end
  end
end
