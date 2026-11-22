# frozen_string_literal: true

require_relative '../lib/ruby/nes'
require_relative '../lib/ruby/nes/frontends/input_script'
require_relative 'benchmark_statistics'
require_relative 'cpu_benchmark'

# The frame benchmark (plan 25): a ROM played from power-up with an input script and audio on, as the window plays it,
# warmed up, then timed over runs of whole frames. Each run prints the digest of its last frame and of the audio, so a
# change that alters the output shows at once (plan 25, decision 3). Reuses the CPU benchmark's configurations.
module FrameBenchmark
  class Error < StandardError; end

  class MissingRom < Error; end
end

require_relative 'frame_benchmark/sample'
require_relative 'frame_benchmark/summary'
require_relative 'frame_benchmark/workload'
require_relative 'frame_benchmark/session'
require_relative 'frame_benchmark/options'
require_relative 'frame_benchmark/command_line'
require_relative 'frame_benchmark/report'
