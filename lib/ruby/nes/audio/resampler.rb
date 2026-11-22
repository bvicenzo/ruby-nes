# frozen_string_literal: true

module Ruby
  module Nes
    module Audio
      # A box resampler (plan 24, decision 4): the APU adds its level every CPU cycle, and at the end of each output
      # period the mean of that period's levels goes to the output. The period is an exact fraction of cycles: each
      # cycle adds the output rate × the input rate's denominator to a phase, and a sample is due each time the phase
      # reaches the input rate's numerator. Hot path (once per CPU cycle with audio on): integers and floats only.
      class Resampler
        # The CPU clock: the master clock, "236.25 MHz ÷ 11 by definition", ÷ 12
        # (https://www.nesdev.org/wiki/Cycle_reference_chart), so 945 000 000 / 528 Hz.
        CPU_CLOCK_RATE = Rational(945_000_000, 4 * 11 * 12)

        # `input_rate` (levels per second) is an Integer or a Rational.
        def initialize(output_rate:, output:, input_rate: CPU_CLOCK_RATE)
          @output = output
          @phase_step = output_rate * input_rate.denominator
          @phase_per_sample = input_rate.numerator
          @phase = 0
          @sum = 0.0
          @count = 0
        end

        def add(level)
          @sum += level
          @count += 1
          @phase += @phase_step
          return if @phase < @phase_per_sample

          @phase -= @phase_per_sample
          @output.push(@sum / @count)
          @sum = 0.0
          @count = 0
        end
      end
    end
  end
end
