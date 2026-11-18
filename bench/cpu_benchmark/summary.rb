# frozen_string_literal: true

module CpuBenchmark
  # What the measured runs of one configuration say: the median speed in emulated MHz, that speed relative to the real
  # console, and how far the runs strayed from the median (the variance plan 10 documents).
  class Summary
    # The NTSC CPU clock, master ÷ 12 (https://www.nesdev.org/wiki/Cycle_reference_chart).
    NTSC_CPU_MEGAHERTZ = 1.789773
    PERCENT = 100.0

    def initialize(samples)
      @speeds = samples.map(&:megahertz).sort
    end

    # The median: the middle speed, or the mean of the two middle ones when the count is even.
    def megahertz
      middle = @speeds.size / 2
      return @speeds[middle] if @speeds.size.odd?

      (@speeds[middle - 1] + @speeds[middle]) / 2
    end

    # 100 is full speed: the emulated CPU keeps pace with the real one.
    def percent_of_real_time = megahertz / NTSC_CPU_MEGAHERTZ * PERCENT

    # The largest distance of a run from the median, as a percentage of the median.
    def spread
      median = megahertz
      farthest_distance = @speeds.map { |speed| (speed - median).abs }.max
      farthest_distance / median * PERCENT
    end
  end
end
