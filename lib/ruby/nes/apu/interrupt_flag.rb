# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # An APU interrupt flag, the frame counter's (https://www.nesdev.org/wiki/APU_Frame_Counter) or the DMC's
      # (https://www.nesdev.org/wiki/APU_DMC): set by its unit unless inhibited (the frame counter's $4017 bit 6, the
      # DMC's $4010 bit 7 clear), it drives the CPU's IRQ line as `source`, each change stamped with its CPU cycle (plan
      # 22, decision 6). Inhibiting clears it. A $4015 read clears the frame counter's, even on the cycle the sequence
      # set it: the APU page's "it will not be cleared" contradicts apu_test's 6-irq_flag_timing, written against the
      # console (plan 22, decision 7); a $4015 write clears the DMC's, and reset both. The CPU is given through the
      # writer, as the Console builds it after the APU.
      class InterruptFlag
        attr_writer :cpu

        def initialize(source:, cpu: nil)
          @source = source
          @cpu = cpu
          @flag = false
          @inhibited = false
        end

        def flag? = @flag

        # The unit sets the flag on `cycle`.
        def trigger(cycle)
          return if @inhibited

          @flag = true
          @cpu.assert_irq(@source, cycle)
        end

        # A $4015 read on `cycle`: the flag as it reads, cleared afterwards.
        def read(cycle)
          flag = @flag
          clear(cycle) if flag
          flag
        end

        # A register write on `cycle` that inhibits the flag or lets it be set.
        def change_inhibit(inhibited, cycle)
          @inhibited = inhibited
          clear(cycle) if inhibited
        end

        # A $4015 write (the DMC's flag) or reset (both): "At power and reset, IRQ flag is clear" (apu_reset's readme;
        # plan 22, decision 4).
        def clear(cycle)
          @flag = false
          @cpu.release_irq(@source, cycle)
        end
      end
    end
  end
end
