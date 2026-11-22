# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The triangle's 32-step sequencer (https://www.nesdev.org/wiki/APU_Triangle): 15 down to 0, then 0 up to 15.
      # Reset puts it back on its first step, "Triangle phase … 0 (output = 15)"
      # (https://www.nesdev.org/wiki/CPU_power_up_state). Hot path: stepped by the triangle's timer, read for the mixer.
      class TriangleSequencer
        # 15 down to 0, then 0 up to 15.
        SEQUENCE = [*15.downto(0), *0.upto(15)].freeze
        # Thirty-two steps: the step wraps within 5 bits.
        STEP_MASK = 0x1F

        def initialize
          @step = 0
        end

        def step
          @step = (@step + 1) & STEP_MASK # glossary: low-bits
        end

        def reset
          @step = 0
        end

        # 0-15.
        def output = SEQUENCE[@step]
      end
    end
  end
end
