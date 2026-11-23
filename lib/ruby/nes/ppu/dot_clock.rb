# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The PPU's elapsed dots since it was built, a count that never wraps; MMC3's A12 filter reads it through
      # `Ppu#elapsed_dots` (plan 21, decision 2). Shared by the Ppu, which ticks it into each range of dots it runs and
      # sets it to the range's last dot, and the renderer, which sets it to each dot of the range before that dot's
      # fetches, so the board sees the dot of every fetch (plan 28, decision 5). Hot path: an integer.
      class DotClock
        attr_accessor :elapsed_dots

        def initialize
          @elapsed_dots = 0
        end

        def tick
          @elapsed_dots += 1
        end
      end
    end
  end
end
