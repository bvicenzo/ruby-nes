# frozen_string_literal: true

# The CPU benchmark of plan 10. Run it under the JIT to measure, one process per configuration and variant:
#
#   ruby --yjit bench/cpu.rb --variant memory_string
#
# `rake bench:cpu` and `rake bench:variants` run every configuration and append the results to docs/benchmarks.md.
require_relative 'cpu_benchmark'

begin
  CpuBenchmark::CommandLine.new(ARGV).run
rescue OptionParser::ParseError, CpuBenchmark::Error => error
  abort error.message
end
