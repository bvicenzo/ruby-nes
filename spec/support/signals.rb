# frozen_string_literal: true

# Test signals for the audio filters and resampler (plan 24), in levels, one per sample:
#
#   sine_wave(frequency: 90, sample_rate: 48_000, count: 24_000)  # half a second of a 90 Hz sine, amplitude 1
#   steady_amplitude(output, frequency: 90, sample_rate: 48_000)  # the peak of the output's last period
module Signals
  def sine_wave(frequency:, sample_rate:, count:)
    Array.new(count) { |index| Math.sin(2 * Math::PI * frequency * index / sample_rate) }
  end

  # The largest magnitude over the last period of a sine of `frequency`: its amplitude once a filter has settled.
  def steady_amplitude(levels, frequency:, sample_rate:)
    levels.last((sample_rate / frequency.to_f).ceil).map(&:abs).max
  end
end

RSpec.configure { |config| config.include(Signals) }
