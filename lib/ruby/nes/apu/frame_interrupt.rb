# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The frame counter's interrupt flag (https://www.nesdev.org/wiki/APU_Frame_Counter): set by the 4-step sequence
      # unless the inhibit flag ($4017 bit 6) is set, it drives the CPU's IRQ line as the FRAME_IRQ source, each change
      # stamped with its CPU cycle (plan 22, decision 6). Setting the inhibit flag clears it, and so does a $4015 read,
      # even on the cycle the sequence set it: the APU page's "it will not be cleared" contradicts apu_test's
      # 6-irq_flag_timing, written against the console (plan 22, decision 7). The CPU is given through the writer, as
      # the Console builds it after the APU.
      class FrameInterrupt
        attr_writer :cpu

        def initialize(cpu: nil)
          @cpu = cpu
          @flag = false
          @inhibited = false
        end

        def flag? = @flag

        # The sequence sets the flag on `cycle`.
        def trigger(cycle)
          return if @inhibited

          @flag = true
          @cpu.assert_irq(Cpu::InterruptLines::FRAME_IRQ, cycle)
        end

        # A $4015 read on `cycle`: the flag as it reads, cleared afterwards.
        def read(cycle)
          flag = @flag
          clear(cycle) if flag
          flag
        end

        # A $4017 write on `cycle`, with bit 6 as `inhibited`.
        def change_inhibit(inhibited, cycle)
          @inhibited = inhibited
          clear(cycle) if inhibited
        end

        # "At power and reset, IRQ flag is clear" (apu_reset's readme; plan 22, decision 4).
        def reset(cycle)
          clear(cycle)
        end

        private

        def clear(cycle)
          @flag = false
          @cpu.release_irq(Cpu::InterruptLines::FRAME_IRQ, cycle)
        end
      end
    end
  end
end
