# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The pulse channel's 8-step sequencer (https://www.nesdev.org/wiki/APU_Pulse). The duty picks a row of the
      # hardware's lookup table, read "in the order 0, 7, 6, 5, 4, 3, 2, 1": the step counts down from 0, so the
      # waveforms play as 0 1 0 0 0 0 0 0, 0 1 1 0 0 0 0 0, 0 1 1 1 1 0 0 0 and 1 0 0 1 1 1 1 1. Hot path: stepped
      # by the timer, read every APU cycle.
      class DutySequencer
        # The lookup table, one row per duty, as the page lists it.
        WAVEFORMS = [
          [0, 0, 0, 0, 0, 0, 0, 1],
          [0, 0, 0, 0, 0, 0, 1, 1],
          [0, 0, 0, 0, 1, 1, 1, 1],
          [1, 1, 1, 1, 1, 1, 0, 0]
        ].freeze
        # Eight steps: the step wraps within 3 bits.
        STEP_MASK = 0x07

        def initialize
          @waveform = WAVEFORMS.first
          @step = 0
        end

        # Bits 7-6 of the channel's first register.
        def duty=(duty)
          @waveform = WAVEFORMS[duty]
        end

        # A write to the channel's fourth register: back to the first step.
        def restart
          @step = 0
        end

        # The timer clocks the sequencer.
        def step
          @step = (@step - 1) & STEP_MASK # glossary: low-bits
        end

        # 0 or 1.
        def output = @waveform[@step]
      end
    end
  end
end
