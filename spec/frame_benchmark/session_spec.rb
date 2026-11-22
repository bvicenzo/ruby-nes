# frozen_string_literal: true

require_relative '../../bench/frame_benchmark'

RSpec.describe FrameBenchmark::Session do
  describe '#measure' do
    context 'when there are no warm-up frames' do
      subject(:session) { described_class.new(workload:, warm_up_frames: 0, frames_per_run: 60, measured_runs: 2) }

      let(:workload) { instance_double(FrameBenchmark::Workload) }

      before { allow(workload).to receive(:run).and_return(FrameBenchmark::Sample.new(frames: 60, seconds: 1.0)) }

      it 'plays only the measured runs', :aggregate_failures do
        session.measure
        expect(workload).to have_received(:run).with(frames: 60).twice
        expect(workload).to have_received(:run).twice
      end
    end

    context 'when there are warm-up frames' do
      subject(:session) { described_class.new(workload:, warm_up_frames: 1200, frames_per_run: 60, measured_runs: 3) }

      let(:workload) { instance_double(FrameBenchmark::Workload) }
      let(:warm_up_sample) { FrameBenchmark::Sample.new(frames: 1200, seconds: 1.0) }
      let(:measured_samples) do
        [
          FrameBenchmark::Sample.new(frames: 60, seconds: 1.0),
          FrameBenchmark::Sample.new(frames: 60, seconds: 2.0),
          FrameBenchmark::Sample.new(frames: 60, seconds: 4.0)
        ]
      end

      before { allow(workload).to receive(:run).and_return(warm_up_sample, *measured_samples) }

      it 'plays them in one run before the measured runs', :aggregate_failures do
        session.measure
        expect(workload).to have_received(:run).with(frames: 1200).once.ordered
        expect(workload).to have_received(:run).with(frames: 60).exactly(3).times.ordered
      end

      # The warm-up ran at 1200 frames per second: counting it would pull the median far above 30.
      it 'summarises only the measured runs' do
        expect(session.measure)
          .to have_attributes(frames_per_second: be_within(1e-9).of(30.0), spread: be_within(1e-9).of(100.0))
      end
    end
  end
end
