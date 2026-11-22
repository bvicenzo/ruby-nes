# frozen_string_literal: true

module Ruby
  module Nes
    module Audio
      # A first-order low-pass filter, the NES's at 14 kHz (https://www.nesdev.org/wiki/APU_Mixer), in the discrete RC
      # form (https://en.wikipedia.org/wiki/Low-pass_filter#Discrete-time_realization): each output moves from the
      # previous one toward the input by beta = dt / (RC + dt). It starts at rest. Near the Nyquist frequency it cuts
      # more than the analogue filter (plan 24, Known gaps). Once per sample: no allocation.
      class LowPassFilter
        def initialize(cutoff:, sample_rate:)
          sample_period = 1.0 / sample_rate
          @beta = sample_period / (Audio.time_constant(cutoff) + sample_period)
          @output = 0.0
        end

        def filter(sample)
          @output += @beta * (sample - @output)
        end
      end
    end
  end
end
