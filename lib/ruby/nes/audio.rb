# frozen_string_literal: true

module Ruby
  module Nes
    # Turns the APU's output, one level per CPU cycle, into the signed 16-bit samples a speaker plays (plan 24): the
    # box resampler, the NES's output filters and the frame's sample buffer. Signal processing, not hardware; the
    # filters model the circuit after the DACs (https://www.nesdev.org/wiki/APU_Mixer).
    module Audio
      # Mono, signed 16-bit samples, 48 000 per second: the macOS output device's own rate (plan 24, decision 1).
      SAMPLE_RATE = 48_000
      BITS_PER_SAMPLE = 16
      CHANNELS = 1

      # The RC time constant of a first-order filter cutting off at `cutoff` hertz: 1 / (2π × cut-off), in seconds.
      def self.time_constant(cutoff) = 1 / (2 * Math::PI * cutoff)
    end
  end
end

require_relative 'audio/high_pass_filter'
require_relative 'audio/low_pass_filter'
require_relative 'audio/sample_buffer'
require_relative 'audio/output_stage'
require_relative 'audio/resampler'
