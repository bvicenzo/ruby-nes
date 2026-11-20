# frozen_string_literal: true

require 'ruby/nes/frontends/monotonic_clock'

# The clock frontends pace and measure frames with: monotonic seconds, the system's CLOCK_MONOTONIC.
RSpec.describe Ruby::Nes::Frontends::MonotonicClock do
  describe '.call' do
    before { allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC).and_return(42.5) }

    it 'reads the monotonic clock' do
      expect(described_class.call).to eq(42.5)
    end
  end
end
