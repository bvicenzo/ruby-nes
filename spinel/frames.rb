# frozen_string_literal: true

# Plan 25's frame benchmark, built to compile with Spinel (plan 26) as well as run on CRuby: the ROM played from
# power-up with the input script and audio on, warmed up, then timed over runs of whole frames, printed as one JSON
# line with the frame and audio digests, the line bench/frame.rb prints. No OptionParser, which Spinel cannot compile
# here: the paths and the workload's size come as arguments, from `rake bench:spinel`.
#
#   spinel/frames.rb ROM INPUT_SCRIPT WARM_UP_FRAMES FRAMES_PER_RUN MEASURED_RUNS
require 'json'
require_relative '../lib/ruby/nes'
require_relative '../lib/ruby/nes/frontends/input_script'
require_relative '../bench/benchmark_statistics'
require_relative '../bench/cpu_benchmark/configuration'
require_relative '../bench/frame_benchmark/sample'
require_relative '../bench/frame_benchmark/summary'
require_relative '../bench/frame_benchmark/workload'
require_relative '../bench/frame_benchmark/session'
require_relative '../bench/frame_benchmark/measurement'

USAGE = 'Usage: spinel/frames.rb ROM INPUT_SCRIPT WARM_UP_FRAMES FRAMES_PER_RUN MEASURED_RUNS'
abort USAGE unless ARGV.size == 5

rom, input, warm_up_frames, frames_per_run, measured_runs = ARGV
workload = FrameBenchmark::Workload.from_files(rom:, input:)
session = FrameBenchmark::Session.new(
  workload:,
  warm_up_frames: Integer(warm_up_frames),
  frames_per_run: Integer(frames_per_run),
  measured_runs: Integer(measured_runs)
)
puts JSON.generate(FrameBenchmark::Measurement.to_h(session.measure, workload))
