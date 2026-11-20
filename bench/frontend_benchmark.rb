# frozen_string_literal: true

require_relative '../lib/ruby/nes'
require_relative '../lib/ruby/nes/frontends/base'
require_relative '../lib/ruby/nes/frontends/driver'
require_relative 'cpu_benchmark/configuration'

# The windowed backend comparison (plans/17-backend-comparison-raylib-sdl3.md): runs a ROM in a backend, times its
# frames and pushes a test tone through its audio stream. Benchmark tooling, never loaded by the emulator; the
# backends' gems are optional (the `frontends` Gemfile group), so a backend is only loaded when it is asked for.
module FrontendBenchmark
end

require_relative 'frontend_benchmark/square_wave'
require_relative 'frontend_benchmark/probe'
require_relative 'frontend_benchmark/summary'
require_relative 'frontend_benchmark/backends'
require_relative 'frontend_benchmark/options'
require_relative 'frontend_benchmark/command_line'
