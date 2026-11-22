# frozen_string_literal: true

# Measures whole frames of a ROM played with an input script, audio on (plan 25): `ruby [--yjit | --zjit]
# bench/frame.rb [--rom PATH] [--input PATH] [--warm-up-frames COUNT] [--frames COUNT] [--runs COUNT]` prints one JSON
# line. `rake bench:frames` runs it under each configuration and appends the table to docs/benchmarks.md.

require_relative 'frame_benchmark'

begin
  FrameBenchmark::CommandLine.new(ARGV).run
rescue OptionParser::ParseError,
       FrameBenchmark::Error,
       Ruby::Nes::Frontends::InputScript::InvalidScript,
       SystemCallError => error
  abort error.message
end
