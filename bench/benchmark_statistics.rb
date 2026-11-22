# frozen_string_literal: true

# The statistics the benchmarks summarise their runs with (plans 10 and 25): the median, and the spread around it.
module BenchmarkStatistics
  PERCENT = 100.0

  # The middle value in order; the mean of the two middle ones for an even count.
  def self.median(values)
    sorted = values.sort
    middle = sorted.size / 2
    return sorted[middle] if sorted.size.odd?

    (sorted[middle - 1] + sorted[middle]).fdiv(2)
  end

  # The largest distance of one value from the median, as a percentage of the median.
  def self.spread(values)
    median = median(values)
    farthest_distance = values.map { |value| (value - median).abs }.max
    farthest_distance.fdiv(median) * PERCENT
  end
end
