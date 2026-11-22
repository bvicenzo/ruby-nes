# frozen_string_literal: true

require_relative '../../bench/frame_benchmark'

RSpec.describe FrameBenchmark::Options do
  describe '.parse' do
    context 'when no option is given' do
      it 'uses the defaults' do
        expect(described_class.parse([])).to have_attributes(
          rom: File.expand_path('../../roms/smb3.nes', __dir__),
          input: File.expand_path('../fixtures/smb3_world_1_1.yml', __dir__),
          warm_up_frames: 1200,
          frames_per_run: 60,
          measured_runs: 5
        )
      end
    end

    context 'with --rom' do
      it 'reads that ROM' do
        expect(described_class.parse(['--rom', 'roms/zelda.nes'])).to have_attributes(rom: 'roms/zelda.nes')
      end
    end

    context 'with --input' do
      it 'reads that input script' do
        expect(described_class.parse(['--input', 'scripts/zelda.yml'])).to have_attributes(input: 'scripts/zelda.yml')
      end
    end

    context 'with --warm-up-frames' do
      context 'but the count is negative' do
        it 'raises InvalidArgument naming the minimum 0' do
          expect { described_class.parse(['--warm-up-frames', '-1']) }
            .to raise_error(OptionParser::InvalidArgument, /--warm-up-frames -1 \(at least 0\)/)
        end
      end

      context 'and the count is 0' do
        it 'warms up no frame' do
          expect(described_class.parse(['--warm-up-frames', '0'])).to have_attributes(warm_up_frames: 0)
        end
      end
    end

    context 'with --frames' do
      context 'but the count is 0' do
        it 'raises InvalidArgument naming the minimum 1' do
          expect { described_class.parse(['--frames', '0']) }
            .to raise_error(OptionParser::InvalidArgument, /--frames 0 \(at least 1\)/)
        end
      end

      context 'and the count is 1' do
        it 'plays runs of one frame' do
          expect(described_class.parse(['--frames', '1'])).to have_attributes(frames_per_run: 1)
        end
      end
    end

    context 'with --runs' do
      context 'but the count is 0' do
        it 'raises InvalidArgument naming the minimum 1' do
          expect { described_class.parse(['--runs', '0']) }
            .to raise_error(OptionParser::InvalidArgument, /--runs 0 \(at least 1\)/)
        end
      end

      context 'and the count is 1' do
        it 'measures one run' do
          expect(described_class.parse(['--runs', '1'])).to have_attributes(measured_runs: 1)
        end
      end
    end
  end
end
