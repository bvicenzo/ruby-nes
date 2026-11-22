# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The triangle's linear counter (https://www.nesdev.org/wiki/APU_Triangle), a finer gate than the length counter.
      # It reads $4008, `CRRR RRRR`: the control flag and the reload value; a $400B write sets its reload flag. On a
      # quarter frame clock a set reload flag reloads the counter, otherwise the counter counts down to 0; then the
      # reload flag clears unless the control flag is set. The triangle's sequencer runs only while it is above 0. It
      # starts at 0 ($4008 is 0 at power, https://www.nesdev.org/wiki/CPU_power_up_state).
      class LinearCounter
        CONTROL_FLAG = 0x80
        RELOAD_VALUE_MASK = 0x7F

        attr_reader :count

        def initialize
          @count = 0
          @reload_value = 0
          @control = false
          @reload = false
        end

        # The channel's first register.
        def write(value)
          @control = value.anybits?(CONTROL_FLAG)
          @reload_value = value & RELOAD_VALUE_MASK # glossary: low-bits
        end

        # A write to the channel's fourth register.
        def restart
          @reload = true
        end

        # A quarter frame clock.
        def clock
          if @reload
            @count = @reload_value
          elsif !@count.zero?
            @count -= 1
          end
          @reload = false unless @control
        end

        def active? = !@count.zero?
      end
    end
  end
end
