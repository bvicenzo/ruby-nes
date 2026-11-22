# frozen_string_literal: true

module Ruby
  module Nes
    module Audio
      # A first-order high-pass filter, the NES's at 90 Hz (https://www.nesdev.org/wiki/APU_Mixer), in the discrete RC
      # form (https://en.wikipedia.org/wiki/High-pass_filter#Discrete-time_realization): each output is alpha × (the
      # previous output + the change of the input), alpha = RC / (RC + dt). It starts at rest and removes the mixer's
      # DC offset. Once per sample: no allocation.
      class HighPassFilter
        def initialize(cutoff:, sample_rate:)
          time_constant = Audio.time_constant(cutoff)
          @alpha = time_constant / (time_constant + (1.0 / sample_rate))
          @previous_input = 0.0
          @previous_output = 0.0
        end

        def filter(sample)
          @previous_output = @alpha * (@previous_output + (sample - @previous_input))
          @previous_input = sample
          @previous_output
        end
      end
    end
  end
end
