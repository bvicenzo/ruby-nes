# frozen_string_literal: true

require_relative '../lib/ruby/nes'
require_relative '../spec/support/test_roms'
require_relative '../spec/support/nestest'

# The CPU benchmark (plans/10-jit-benchmark.md): nestest in automation mode, looped from a fresh console, timed under
# no JIT, YJIT or ZJIT, with optional variants of the hot paths. Benchmark tooling, never loaded by the emulator.
module CpuBenchmark
  # What bench/cpu.rb reports as a one-line message instead of a backtrace.
  class Error < StandardError; end

  # A variant broke the CPU: nestest's result bytes were not zero after a pass, so its cycles must not be measured.
  class BrokenVariant < Error; end
end

require_relative 'cpu_benchmark/workload'
require_relative 'cpu_benchmark/sample'
require_relative 'cpu_benchmark/summary'
require_relative 'cpu_benchmark/session'
require_relative 'cpu_benchmark/configuration'
require_relative 'cpu_benchmark/options'
require_relative 'cpu_benchmark/variants'
require_relative 'cpu_benchmark/command_line'
require_relative 'cpu_benchmark/dispatch_source'
require_relative 'cpu_benchmark/report'
