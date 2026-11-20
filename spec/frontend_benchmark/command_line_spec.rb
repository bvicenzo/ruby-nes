# frozen_string_literal: true

require_relative '../../bench/frontend_benchmark'

require 'json'
require 'stringio'

# bench/frontends.rb (plan 17, decision 2): runs a ROM in a windowed backend through the probe and prints what it
# measured as one JSON line, for `rake bench:frontends` to collect. The backend needs the optional `frontends` group;
# here it runs nestest for 3 frames in a hidden window.
RSpec.describe FrontendBenchmark::CommandLine do
  describe '#run' do
    context 'when the arguments are invalid' do
      subject(:command_line) { described_class.new(%w[game.nes --backend gosu], output: StringIO.new) }

      it 'raises the parse error' do
        expect { command_line.run }.to raise_error(OptionParser::InvalidArgument)
      end
    end

    context(
      'when the raylib backend runs a ROM',
      frontend_library: 'ruby/nes/frontends/raylib',
      test_rom: [Nestest::ROM_PATH]
    ) do
      subject(:command_line) { described_class.new(arguments, output:) }

      let(:arguments) { [test_rom_path(Nestest::ROM_PATH), '--backend', 'raylib', '--frames', '3', '--hidden'] }
      let(:output) { StringIO.new }

      it 'prints the measurement as one JSON line' do
        command_line.run

        expect(JSON.parse(output.string, symbolize_names: true)).to include(
          backend: 'raylib',
          frames: 3,
          present_milliseconds: a_kind_of(Float),
          frame_milliseconds: a_kind_of(Float),
          frames_per_second: a_kind_of(Float)
        )
      end
    end
  end
end
