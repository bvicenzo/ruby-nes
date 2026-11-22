# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # A pulse channel's sweep unit (https://www.nesdev.org/wiki/APU_Sweep, served by the APU Pulse page), written
      # through `EPPP NSSS`. It adjusts the period of the channel's timer on half frame clocks, towards a target period:
      # the period plus or minus the period shifted right by S. Pulse 1 negates with ones' complement and pulse 2 with
      # two's complement, the `negation` each is built with. It mutes the channel when the period is below 8 or the
      # target above $7FF, "regardless of the state of the sweep unit". Muting needs the period at 8 or more, and a
      # shift of at least 1 halves the change, so a negated target never goes below 0: no clamp is needed.
      class Sweep
        # Negating subtracts the change and 1 more on pulse 1 ("Making 20 negative produces a change amount of −21"),
        # the change alone on pulse 2.
        ONES_COMPLEMENT = 1
        TWOS_COMPLEMENT = 0
        # `EPPP NSSS`.
        ENABLED_FLAG = 0x80
        PERIOD_MASK = 0x70
        PERIOD_SHIFT = 4
        NEGATE_FLAG = 0x08
        SHIFT_MASK = 0x07
        # Periods below 8 mute the channel.
        MINIMUM_PERIOD = 8
        # The timer has 11 bits: a target above them mutes the channel.
        MAXIMUM_TARGET = 0x7FF

        def initialize(timer:, negation:)
          @timer = timer
          @negation = negation
          @enabled = false
          @divider_period = 0
          @negate = false
          @shift = 0
          @divider = 0
          @reload = false
        end

        # The channel's second register.
        def write(value)
          @enabled = (value & ENABLED_FLAG) != 0 # glossary: flag-set
          @divider_period = (value & PERIOD_MASK) >> PERIOD_SHIFT # glossary: bit-field
          @negate = (value & NEGATE_FLAG) != 0 # glossary: flag-set
          @shift = value & SHIFT_MASK # glossary: low-bits
          @reload = true
        end

        def muting? = @timer.period < MINIMUM_PERIOD || target_period > MAXIMUM_TARGET

        # A half frame clock.
        def clock
          @timer.period = target_period if @divider.zero? && @enabled && !@shift.zero? && !muting?
          if @divider.zero? || @reload
            @divider = @divider_period
            @reload = false
          else
            @divider -= 1
          end
        end

        private

        def target_period
          period = @timer.period
          change = period >> @shift # glossary: shift-right
          @negate ? period - change - @negation : period + change
        end
      end
    end
  end
end
