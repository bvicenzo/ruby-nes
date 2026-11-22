# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # A channel's envelope (https://www.nesdev.org/wiki/APU_Envelope): a start flag, a divider and a decay level. It
      # reads the low six bits of the channel's first register, `--LC VVVV`. On a quarter frame clock, a set start flag
      # clears and restarts the decay at 15 with the divider reloaded; otherwise the divider counts down V + 1 clocks
      # and then steps the decay level down, back to 15 from 0 when the loop flag is set. The volume is V with the
      # constant volume flag, the decay level without it.
      class Envelope
        # Bit 5: loop the decay (also the length counter's halt flag).
        LOOP_FLAG = 0x20
        # Bit 4: constant volume.
        CONSTANT_VOLUME_FLAG = 0x10
        # Bits 3-0, V: the constant volume, or the divider's reload value.
        VOLUME_MASK = 0x0F
        # The decay level restarts at 15.
        DECAY_START = 15

        def initialize
          @start = false
          @divider = 0
          @decay_level = 0
          @loop = false
          @constant_volume = false
          @volume_or_period = 0
        end

        # The channel's first register.
        def write(value)
          @loop = (value & LOOP_FLAG) != 0 # glossary: flag-set
          @constant_volume = (value & CONSTANT_VOLUME_FLAG) != 0 # glossary: flag-set
          @volume_or_period = value & VOLUME_MASK # glossary: low-bits
        end

        # A write to the channel's fourth register.
        def restart
          @start = true
        end

        # A quarter frame clock.
        def clock
          if @start
            @start = false
            @decay_level = DECAY_START
            @divider = @volume_or_period
          elsif @divider.zero?
            @divider = @volume_or_period
            clock_decay
          else
            @divider -= 1
          end
        end

        def volume = @constant_volume ? @volume_or_period : @decay_level

        private

        def clock_decay
          if !@decay_level.zero?
            @decay_level -= 1
          elsif @loop
            @decay_level = DECAY_START
          end
        end
      end
    end
  end
end
