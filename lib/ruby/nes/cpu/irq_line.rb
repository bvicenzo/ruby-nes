# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # The CPU's IRQ input (https://www.nesdev.org/wiki/CPU_interrupts), "connected to a level detector". It is a
      # wired-OR, as the hardware's open-collector line (architecture decision 25, plan 21 decision 5): each source
      # asserts and releases its own bit, and the line stays asserted while any source asserts it.
      #
      # Each change carries the CPU cycle it happened on (plan 22, decision 6), so a poll sees the line as it stood
      # before its poll cycle: asserted before it and not released before it. A release on the poll cycle or later, such
      # as a $4015 read or a $E000 write on an instruction's last cycle, comes after the poll, and the IRQ is still
      # taken once.
      class IrqLine
        # The line was never released: no poll cycle is below it.
        NEVER_RELEASED = -1

        def initialize
          @sources = 0
          @asserted_cycle = 0
          @released_cycle = NEVER_RELEASED
        end

        # The source pulls the line low on `cycle`; asserting it again, or a second source, keeps the first cycle.
        def assert(source, cycle)
          @asserted_cycle = cycle if @sources.zero?
          @sources |= source # glossary: set-flag
        end

        # The source lets go of the line on `cycle`; the line stays asserted while another source asserts it.
        def release(source, cycle)
          return if (@sources & source) == 0 # glossary: flag-clear

          @sources &= ~source # glossary: clear-flag
          @released_cycle = cycle if @sources.zero?
        end

        # Whether a poll on `poll_cycle` sees the line asserted.
        def asserted_at?(poll_cycle)
          @asserted_cycle < poll_cycle && (!@sources.zero? || @released_cycle >= poll_cycle)
        end
      end
    end
  end
end
