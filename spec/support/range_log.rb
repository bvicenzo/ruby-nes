# frozen_string_literal: true

# A stand-in for Ppu::Renderer that logs each range of dots the Ppu tells it to run, with the dot clock's count when
# told: the count of the range's first dot (plan 28, decision 5).
#
#   renderer = RangeLog.new(clock:)
#   Ruby::Nes::Ppu.new(bus:, clock:, renderer:).catch_up(10)
#   renderer.ranges # => [{ scanline: 100, first_dot: 1, last_dot: 30, elapsed_dots: 1 }]
class RangeLog
  attr_reader :ranges

  def initialize(clock:)
    @clock = clock
    @ranges = []
  end

  def run_dots(scanline, first_dot, last_dot)
    @ranges << { scanline:, first_dot:, last_dot:, elapsed_dots: @clock.elapsed_dots }
  end
end
