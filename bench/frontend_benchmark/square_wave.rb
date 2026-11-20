# frozen_string_literal: true

module FrontendBenchmark
  # The tone of the audio smoke test: a square wave of signed 16-bit samples, +amplitude for the first half of each
  # period and -amplitude for the second. The phase of a sample comes from its index in integers, so a period that is
  # not a whole number of samples (44_100 / 440) does not drift, and consecutive calls continue one wave.
  class SquareWave
    def initialize(frequency:, sample_rate:, amplitude:)
      @frequency = frequency
      @sample_rate = sample_rate
      @amplitude = amplitude
      @next_index = 0
    end

    def samples(count)
      indexes = @next_index...(@next_index + count)
      @next_index += count
      indexes.map { |index| first_half?(index) ? @amplitude : -@amplitude }
    end

    private

    # The sample's position in its period, in 1/sample_rate of a period, is below half of it.
    def first_half?(index) = (index * @frequency % @sample_rate) * 2 < @sample_rate
  end
end
