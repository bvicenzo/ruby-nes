# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The noise channel (https://www.nesdev.org/wiki/APU_Noise), registers $400C-$400F numbered 0-3. Plan 22 brings
      # only its length counter, so that $4015 and the length counter tests see the four main channels (plan 22,
      # decision 8); plan 23 brings the rest.
      class Noise
        # $400C bit 5: the length counter halt (also the envelope's loop flag, plan 23).
        # The registers that reach the length counter, numbered from the channel's first address.
        CONTROL_REGISTER = 0
        LENGTH_REGISTER = 3
        LENGTH_COUNTER_HALT_FLAG = 0x20

        def initialize(length_counter: LengthCounter.new)
          @length_counter = length_counter
        end

        # Register `register` (0-3) of the channel.
        def write(register, value)
          case register
          when CONTROL_REGISTER then @length_counter.halted = value.anybits?(LENGTH_COUNTER_HALT_FLAG)
          when LENGTH_REGISTER then @length_counter.load(value)
          end
        end

        def half_frame
          @length_counter.clock
        end

        def enabled=(enabled)
          @length_counter.enabled = enabled
        end

        def active? = @length_counter.active?
      end
    end
  end
end
