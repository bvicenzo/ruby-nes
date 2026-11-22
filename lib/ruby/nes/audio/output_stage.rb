# frozen_string_literal: true

module Ruby
  module Nes
    module Audio
      # The NES's output circuit for each resampled level (plan 24, decision 5): "A first-order high-pass filter at
      # 90 Hz", then "A first-order low-pass filter at 14 kHz" (https://www.nesdev.org/wiki/APU_Mixer), then a signed
      # 16-bit sample into the frame's samples. A level of 0.0-1.0 (the mixer's) leaves the high-pass within (-1, 1)
      # and the low-pass never overshoots, so the rounded sample stays within 16 bits without clamping. Once per sample.
      class OutputStage
        HIGH_PASS_CUTOFF = 90
        LOW_PASS_CUTOFF = 14_000
        # The largest signed 16-bit sample.
        FULL_SCALE = 32_767

        def initialize(samples:, sample_rate: SAMPLE_RATE,
                       high_pass: HighPassFilter.new(cutoff: HIGH_PASS_CUTOFF, sample_rate:),
                       low_pass: LowPassFilter.new(cutoff: LOW_PASS_CUTOFF, sample_rate:))
          @samples = samples
          @high_pass = high_pass
          @low_pass = low_pass
        end

        def push(level)
          @samples.push((@low_pass.filter(@high_pass.filter(level)) * FULL_SCALE).round)
        end
      end
    end
  end
end
