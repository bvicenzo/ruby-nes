# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      class Mmc3 < Base
        # MMC3's scanline counter (https://www.nesdev.org/wiki/MMC3#IRQ_Specifics), with the "new" behaviour of the
        # Sharp MMC3B/C (plan 21, decision 3): on a clock, the counter loads the latch when it is 0 and decrements
        # otherwise; if it is 0 afterwards and IRQs are enabled, the IRQ is asserted. With the latch at 0 that asserts
        # the IRQ on every clock ("generate an IRQ on each scanline while $C000 is $00"). $C001 clears the counter at
        # once, without an IRQ; $C000 only changes the latch; $E000 disables and acknowledges, "the counter will
        # continue to run"; $E001 enables. Everything starts at 0, disabled (plan 19, decision 6). The CPU is the IRQ
        # line, through its MAPPER_IRQ source (plan 21, decision 5), told with the cycle of each change (plan 22,
        # decision 6). Clocked once per filtered A12 rise, about once per scanline: no allocation.
        class IrqCounter
          attr_writer :cpu, :latch

          def initialize(cpu: nil)
            @cpu = cpu
            @latch = 0
            @counter = 0
            @enabled = false
          end

          # A filtered A12 rise on CPU cycle `cycle`.
          def clock(cycle)
            if @counter.zero?
              @counter = @latch
            else
              @counter -= 1
            end
            @cpu.assert_irq(Cpu::InterruptLines::MAPPER_IRQ, cycle) if @counter.zero? && @enabled
          end

          # $C001: the counter is cleared now, so it loads the latch on the next clock. The wiki's reload flag changes
          # nothing more in the "new" behaviour: it is only set while the counter is 0.
          def request_reload
            @counter = 0
          end

          # $E000: no more IRQs, and the one asserted is acknowledged on the write's cycle.
          def disable
            @enabled = false
            @cpu.release_irq(Cpu::InterruptLines::MAPPER_IRQ, @cpu.access_cycle)
          end

          # $E001.
          def enable
            @enabled = true
          end
        end
      end
    end
  end
end
