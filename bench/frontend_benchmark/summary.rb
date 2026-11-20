# frozen_string_literal: true

module FrontendBenchmark
  # One series of durations a probe timed, in seconds, summed up by its median: the middle duration, or the mean of the
  # two middle ones when the count is even (as CpuBenchmark::Summary takes it). An empty series, as a window closed
  # after one frame leaves between frames, has no median.
  class Summary
    MILLISECONDS_PER_SECOND = 1000.0

    def initialize(seconds)
      @seconds = seconds.sort
    end

    def median_milliseconds
      median_seconds&.then { it * MILLISECONDS_PER_SECOND }
    end

    # How many durations as long as the median fit in one second: frames per second for a series of frames.
    def per_second
      median_seconds&.then { 1 / it }
    end

    private

    def median_seconds
      return if @seconds.empty?

      middle = @seconds.size / 2
      return @seconds[middle] if @seconds.size.odd?

      (@seconds[middle - 1] + @seconds[middle]) / 2
    end
  end
end
