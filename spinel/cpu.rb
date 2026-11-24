# frozen_string_literal: true

# Plan 10's CPU benchmark, built to compile with Spinel (plan 26) as well as run on CRuby: the trace is checked
# against the whole of nestest.log, then the workload is measured and printed as one JSON line, the line bench/cpu.rb
# prints for its baseline. No OptionParser, no variants and no test ROM manifest, which Spinel cannot compile here: the
# paths and the workload's size come as arguments, from `rake bench:spinel`.
#
#   spinel/cpu.rb NESTEST_ROM NESTEST_LOG CYCLES WARM_UP_RUNS MEASURED_RUNS
require 'json'
require_relative '../lib/ruby/nes'
require_relative '../spec/support/nestest'
require_relative '../bench/benchmark_statistics'
require_relative '../bench/cpu_benchmark/errors'
require_relative '../bench/cpu_benchmark/workload'
require_relative '../bench/cpu_benchmark/sample'
require_relative '../bench/cpu_benchmark/summary'
require_relative '../bench/cpu_benchmark/session'
require_relative '../bench/cpu_benchmark/configuration'
require_relative '../bench/cpu_benchmark/measurement'

USAGE = 'Usage: spinel/cpu.rb NESTEST_ROM NESTEST_LOG CYCLES WARM_UP_RUNS MEASURED_RUNS'
abort USAGE unless ARGV.size == 5

rom_path, log_path, cycles, warm_up_runs, measured_runs = ARGV
cartridge = Ruby::Nes::Cartridge::Loader.from_file(rom_path)
log_lines = Nestest::Log.lines(File.read(log_path))
divergence = Nestest::Runner.automation_mode(cartridge).first_divergence(log_lines)
abort divergence.message if divergence

workload = CpuBenchmark::Workload.new(cartridge, steps_per_pass: log_lines.size)
session = CpuBenchmark::Session.new(
  workload:,
  cycles: Integer(cycles),
  warm_up_runs: Integer(warm_up_runs),
  measured_runs: Integer(measured_runs)
)
puts JSON.generate(CpuBenchmark::Measurement.to_h(session.measure, variant: 'baseline'))
