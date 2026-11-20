# frozen_string_literal: true

# The windowed backend comparison of plan 17. Run a ROM in a backend until its window closes, or measure a number of
# frames under the JIT this process runs with:
#
#   ruby bench/frontends.rb ROM --backend raylib [--frames COUNT] [--tone]
#   ruby --yjit bench/frontends.rb ROM --backend raylib --frames 600
#
# `rake bench:frontends` runs every backend under every JIT and prints the table. The backend's gem is in the
# optional `frontends` Gemfile group: `bundle config set --local with frontends`.
require_relative 'frontend_benchmark'

begin
  FrontendBenchmark::CommandLine.new(ARGV).run
rescue OptionParser::ParseError, Ruby::Nes::Error, LoadError, SystemCallError => error
  abort error.message
end
