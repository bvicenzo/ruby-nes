# frozen_string_literal: true

module CpuBenchmark
  # What the measured runs of one configuration say: the median speed in emulated MHz, that speed relative to the real
  # console, and how far the runs strayed from the median (the variance plan 10 documents).
  class Summary
    # The NTSC CPU clock, master ÷ 12 (https://www.nesdev.org/wiki/Cycle_reference_chart).
    NTSC_CPU_MEGAHERTZ = 1.789773

    def initialize(samples)
      @speeds = samples.map(&:megahertz)
    end

    def megahertz = BenchmarkStatistics.median(@speeds)

    # 100 is full speed: the emulated CPU keeps pace with the real one.
    def percent_of_real_time = megahertz / NTSC_CPU_MEGAHERTZ * BenchmarkStatistics::PERCENT

    # The largest distance of a run from the median, as a percentage of the median.
    def spread = BenchmarkStatistics.spread(@speeds)
  end
end
