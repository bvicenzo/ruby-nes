# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The noise channel's 15-bit linear feedback shift register (https://www.nesdev.org/wiki/APU_Noise). Each clock
      # shifts it right and puts in bit 14 the exclusive-or of bit 0 and a tap: bit 6 in periodic mode ($400E bit 7),
      # bit 1 otherwise. It mutes the channel while bit 0 is set. It holds 1 at power (plan 23, decision 6), and reset
      # leaves it alone. Hot path: clocked by the noise timer.
      class NoiseShiftRegister
        POWER_UP_VALUE = 0x0001
        # The bit the feedback enters.
        FEEDBACK_BIT = 14
        # The bit exclusive-ored with bit 0: bit 1, or bit 6 in periodic mode.
        NORMAL_TAP = 1
        PERIODIC_TAP = 6
        LOWEST_BIT = 0x01

        attr_reader :value

        def initialize(value: POWER_UP_VALUE)
          @value = value
          @tap = NORMAL_TAP
        end

        # Bit 7 of $400E.
        def periodic=(periodic)
          @tap = periodic ? PERIODIC_TAP : NORMAL_TAP
        end

        def step
          tap_bit = (@value >> @tap) & LOWEST_BIT # glossary: bit-at
          feedback = (@value & LOWEST_BIT) ^ tap_bit # glossary: bitwise-and, bitwise-exclusive-or
          shifted = @value >> 1 # glossary: shift-right
          @value = shifted | (feedback << FEEDBACK_BIT) # glossary: shift-left, bitwise-or
        end

        def muting?
          (@value & LOWEST_BIT) != 0 # glossary: flag-set
        end
      end
    end
  end
end
