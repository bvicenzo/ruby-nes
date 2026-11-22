# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The APU mixer (https://www.nesdev.org/wiki/APU_Mixer): the pulses go through one non-linear digital-to-analog
      # converter, the triangle, noise and DMC through another, and the outputs add up to 0.0-1.0. Both converters are
      # the page's lookup tables (plan 23, decision 5), within 0.5% of its exact formulas; a silent group is 0. Hot
      # path: two constant table reads.
      module Mixer
        # "pulse_table[n] = 95.52 / (8128.0 / n + 100)", n = pulse1 + pulse2.
        PULSE_NUMERATOR = 95.52
        PULSE_DIVIDEND = 8128.0
        PULSE_TABLE_SIZE = 31
        # "tnd_table[n] = 163.67 / (24329.0 / n + 100)", n = 3 * triangle + 2 * noise + dmc.
        TRIANGLE_NOISE_DMC_NUMERATOR = 163.67
        TRIANGLE_NOISE_DMC_DIVIDEND = 24_329.0
        TRIANGLE_NOISE_DMC_TABLE_SIZE = 203
        TRIANGLE_WEIGHT = 3
        NOISE_WEIGHT = 2
        # Both tables add 100 to the quotient.
        DIVISOR_OFFSET = 100

        # "When the values for one of the groups are all zero, the result for that group should be treated as zero".
        def self.table(size, numerator, dividend)
          Array.new(size) { |index| index.zero? ? 0.0 : numerator / ((dividend / index) + DIVISOR_OFFSET) }.freeze
        end
        private_class_method :table

        PULSE_TABLE = table(PULSE_TABLE_SIZE, PULSE_NUMERATOR, PULSE_DIVIDEND)
        TRIANGLE_NOISE_DMC_TABLE = table(
          TRIANGLE_NOISE_DMC_TABLE_SIZE, TRIANGLE_NOISE_DMC_NUMERATOR, TRIANGLE_NOISE_DMC_DIVIDEND
        )

        # The pulses' and the triangle's and noise's 0-15 outputs and the DMC's 0-127 level, mixed into 0.0-1.0.
        def self.mix(first_pulse, second_pulse, triangle, noise, dmc)
          PULSE_TABLE[first_pulse + second_pulse] +
            TRIANGLE_NOISE_DMC_TABLE[(TRIANGLE_WEIGHT * triangle) + (NOISE_WEIGHT * noise) + dmc]
        end
      end
    end
  end
end
