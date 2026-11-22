# frozen_string_literal: true

module FrameBenchmark
  # The measured runs summarised: the median rate, the time per frame at it, its share of a real console's rate and the
  # spread of the runs around it.
  class Summary
    # "60.0988 Hz" on NTSC (https://www.nesdev.org/wiki/Cycle_reference_chart).
    NTSC_FRAMES_PER_SECOND = 60.0988
    MILLISECONDS_PER_SECOND = 1000.0

    def initialize(samples)
      @rates = samples.map(&:frames_per_second)
    end

    def frames_per_second = BenchmarkStatistics.median(@rates)

    def milliseconds_per_frame = MILLISECONDS_PER_SECOND / frames_per_second

    def percent_of_real_time = frames_per_second / NTSC_FRAMES_PER_SECOND * BenchmarkStatistics::PERCENT

    def spread = BenchmarkStatistics.spread(@rates)
  end
end
