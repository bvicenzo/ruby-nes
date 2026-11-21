# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # A channel's timer (https://www.nesdev.org/wiki/APU_Pulse): a divider counting t, t-1, ..., 0, t, ..., that
      # clocks the channel's sequencer (anything that answers `step`) on the transition back to t. Its period starts at
      # 0 (https://www.nesdev.org/wiki/CPU_power_up_state). Hot path: ticked every APU cycle.
      class Timer
        attr_accessor :period

        def initialize(sequencer:)
          @sequencer = sequencer
          @period = 0
          @counter = 0
        end

        def tick
          if @counter.zero?
            @counter = @period
            @sequencer.step
          else
            @counter -= 1
          end
        end
      end
    end
  end
end
