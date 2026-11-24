# frozen_string_literal: true

module CpuBenchmark
  # One configuration's measurement as bench/cpu.rb and spinel/cpu.rb print it, one JSON line that
  # CpuBenchmark::Report turns into a row.
  module Measurement
    def self.to_h(summary, variant:)
      {
        configuration: Configuration.current,
        variant:,
        megahertz: summary.megahertz,
        percent_of_real_time: summary.percent_of_real_time,
        spread: summary.spread,
        ruby: RUBY_DESCRIPTION
      }
    end
  end
end
