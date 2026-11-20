# frozen_string_literal: true

require_relative '../../bench/frontend_benchmark'

# One series of durations a probe timed (the presents, or the frames), summed up by its median (plan 17: the median
# over 600 frames).
RSpec.describe FrontendBenchmark::Summary do
  describe '#median_milliseconds' do
    context 'when nothing was timed' do
      subject(:summary) { described_class.new([]) }

      it 'is nil' do
        expect(summary.median_milliseconds).to be_nil
      end
    end

    context 'when one duration was timed' do
      subject(:summary) { described_class.new([0.004]) }

      it 'is that duration' do
        expect(summary.median_milliseconds).to be_within(1e-9).of(4.0)
      end
    end

    context 'when an odd number were timed' do
      subject(:summary) { described_class.new([0.009, 0.002, 0.004]) }

      it 'is the middle one' do
        expect(summary.median_milliseconds).to be_within(1e-9).of(4.0)
      end
    end

    context 'when an even number were timed' do
      subject(:summary) { described_class.new([0.009, 0.002, 0.006, 0.004]) }

      it 'is the mean of the two middle ones' do
        expect(summary.median_milliseconds).to be_within(1e-9).of(5.0)
      end
    end
  end

  describe '#per_second' do
    context 'when nothing was timed' do
      subject(:summary) { described_class.new([]) }

      it 'is nil' do
        expect(summary.per_second).to be_nil
      end
    end

    context 'when durations were timed' do
      subject(:summary) { described_class.new([0.04, 0.05, 0.06]) }

      it 'is how many fit in a second at the median' do
        expect(summary.per_second).to be_within(1e-9).of(20.0)
      end
    end
  end
end
