# frozen_string_literal: true

module CpuBenchmark
  # What bench/cpu.rb reports as a one-line message instead of a backtrace.
  class Error < StandardError; end

  # A variant broke the CPU: nestest's result bytes were not zero after a pass, so its cycles must not be measured.
  class BrokenVariant < Error; end
end
