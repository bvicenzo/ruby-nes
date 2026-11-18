# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

RSpec.describe CpuBenchmark::Options do
  describe '.parse' do
    context 'when an option is unknown' do
      it 'raises OptionParser::InvalidOption' do
        expect { described_class.parse(['--frames', '3']) }.to raise_error(OptionParser::InvalidOption)
      end
    end

    context 'when a count is not a whole number' do
      it 'raises OptionParser::InvalidArgument' do
        expect { described_class.parse(['--runs', '2.5']) }.to raise_error(OptionParser::InvalidArgument)
      end
    end

    context 'when the cycles are not positive' do
      it 'raises OptionParser::InvalidArgument' do
        expect { described_class.parse(['--cycles', '0']) }.to raise_error(OptionParser::InvalidArgument, /--cycles/)
      end
    end

    context 'when the measured runs are not positive' do
      it 'raises OptionParser::InvalidArgument' do
        expect { described_class.parse(['--runs', '0']) }.to raise_error(OptionParser::InvalidArgument, /--runs/)
      end
    end

    context 'when the warm-up runs are negative' do
      it 'raises OptionParser::InvalidArgument' do
        expect { described_class.parse(['--warm-up-runs', '-1']) }
          .to raise_error(OptionParser::InvalidArgument, /--warm-up-runs/)
      end
    end

    context 'when every option is at its minimum' do
      let(:arguments) { ['--variant', 'memory_string', '--cycles', '1', '--warm-up-runs', '0', '--runs', '1'] }

      it 'takes each one' do
        expect(described_class.parse(arguments))
          .to have_attributes(variant: 'memory_string', cycles: 1, warm_up_runs: 0, measured_runs: 1)
      end
    end

    context 'when no option is given' do
      it 'measures the baseline with the default workload' do
        expect(described_class.parse([]))
          .to have_attributes(variant: 'baseline', cycles: 10_000_000, warm_up_runs: 2, measured_runs: 5)
      end
    end
  end
end
