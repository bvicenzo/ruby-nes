# frozen_string_literal: true

require_relative '../../bench/frame_benchmark'

require 'json'
require 'stringio'
require 'tempfile'

RSpec.describe FrameBenchmark::CommandLine do
  describe '#run' do
    context 'when the ROM does not exist' do
      subject(:command_line) { described_class.new(['--rom', 'roms/absent.nes'], output: StringIO.new) }

      it 'raises MissingRom naming it and where a dump goes' do
        expect { command_line.run }.to raise_error(
          FrameBenchmark::MissingRom,
          'Local ROM absent (roms/absent.nes): place a dump of your own cartridge there (never committed)'
        )
      end
    end

    context 'when the ROM exists', test_rom: [Nestest::ROM_PATH] do
      context 'but the input script does not exist' do
        subject(:command_line) { described_class.new(arguments, output: StringIO.new) }

        let(:arguments) { ['--rom', test_rom_path(Nestest::ROM_PATH), '--input', 'scripts/absent.yml'] }

        it 'lets Errno::ENOENT through' do
          expect { command_line.run }.to raise_error(Errno::ENOENT, %r{scripts/absent.yml})
        end
      end

      context 'and the input script exists' do
        subject(:command_line) { described_class.new(arguments, output:) }

        let(:input_script) do
          Tempfile.create(['input', '.yml']).tap do |file|
            file.write("1: [start]\n")
            file.close
          end
        end
        let(:arguments) do
          [
            '--rom',
            test_rom_path(Nestest::ROM_PATH),
            '--input',
            input_script.path,
            '--warm-up-frames',
            '0',
            '--frames',
            '1',
            '--runs',
            '1'
          ]
        end
        let(:output) { StringIO.new }

        after { File.delete(input_script.path) }

        it 'prints one JSON line with the configuration, the speeds, the digests and the Ruby' do
          command_line.run
          expect(JSON.parse(output.string, symbolize_names: true)).to include(
            configuration: CpuBenchmark::Configuration.current,
            frames_per_second: be_positive,
            milliseconds_per_frame: be_positive,
            percent_of_real_time: be_positive,
            spread: 0.0,
            frame_digest: match(/\A\h{64}\z/),
            audio_digest: match(/\A\h{64}\z/),
            ruby: RUBY_DESCRIPTION
          )
        end
      end
    end
  end
end
