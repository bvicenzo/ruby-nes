# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # A channel's length counter (https://www.nesdev.org/wiki/APU_Length_Counter): loaded from a 32-entry table when
      # the channel is enabled, decremented by each half frame clock unless it is 0 or halted, forced to 0 while the
      # channel is disabled ("cannot be changed until enabled is set again"). The channel sounds while it is above 0.
      # It starts disabled, at 0 (https://www.nesdev.org/wiki/CPU_power_up_state).
      class LengthCounter
        # The length table, indexed by bits 7-3 of the channel's fourth register, `LLLL L---`.
        INDEX_SHIFT = 3
        TABLE = [
          10,
          254,
          20,
          2,
          40,
          4,
          80,
          6,
          160,
          8,
          60,
          10,
          14,
          12,
          26,
          14,
          12,
          16,
          24,
          18,
          48,
          20,
          96,
          22,
          192,
          24,
          72,
          26,
          16,
          28,
          32,
          30
        ].freeze

        attr_reader :count
        attr_writer :halted

        def initialize
          @count = 0
          @enabled = false
          @halted = false
        end

        # Enabling has no immediate effect; disabling forces the counter to 0.
        def enabled=(enabled)
          @enabled = enabled
          @count = 0 unless enabled
        end

        # A write of `value` to the channel's fourth register: loads the table entry its bits 7-3 select, if the channel
        # is enabled.
        def load(value)
          @count = TABLE[value >> INDEX_SHIFT] if @enabled # glossary: shift-right
        end

        # A half frame clock.
        def clock
          @count -= 1 unless @count.zero? || @halted
        end

        def active? = !@count.zero?
      end
    end
  end
end
