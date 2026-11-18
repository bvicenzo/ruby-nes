# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

RSpec.describe CpuBenchmark::Session do
  describe '#measure' do
    subject(:session) { described_class.new(workload:, cycles: 1_000_000, warm_up_runs: 2, measured_runs: 3) }

    let(:workload) { instance_double(CpuBenchmark::Workload) }
    let(:warm_up_sample) { CpuBenchmark::Sample.new(cycles: 1_000_000, seconds: 100.0) }
    let(:measured_samples) do
      [
        CpuBenchmark::Sample.new(cycles: 1_000_000, seconds: 1.0),
        CpuBenchmark::Sample.new(cycles: 1_000_000, seconds: 2.0),
        CpuBenchmark::Sample.new(cycles: 1_000_000, seconds: 4.0)
      ]
    end

    before { allow(workload).to receive(:run).and_return(warm_up_sample, warm_up_sample, *measured_samples) }

    it 'runs the workload for every warm-up run and every measured run' do
      session.measure
      expect(workload).to have_received(:run).with(cycles: 1_000_000).exactly(5).times
    end

    # The warm-up runs took 100 seconds each: counting them would pull the median far below 0.5 MHz.
    it 'summarises only the measured runs' do
      expect(session.measure).to have_attributes(megahertz: be_within(1e-9).of(0.5), spread: be_within(1e-9).of(100.0))
    end
  end
end
