# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # The CPU's NMI and IRQ inputs (https://www.nesdev.org/wiki/CPU_interrupts), both released at first. Devices set
      # each line to its level, `true` while asserted and `false` while released (booleans only: the integer 0 would
      # read as asserted); the CPU asks, before each instruction, which interrupt to take.
      #
      # NMI is edge-sensitive: a released-to-asserted change leaves an NMI pending, and the signal "stays high until
      # the NMI has been handled", so releasing the line does not cancel it and holding it asserted does not repeat it.
      # IRQ is level-sensitive and masked by the status's I. "If both an NMI and an IRQ are pending at the end of an
      # instruction, the NMI will be handled".
      #
      # The NMI edge carries the first CPU cycle whose φ2 sample sees it, and what the poll sees is "the status of the
      # interrupt lines at the end of the second-to-last cycle" of the previous instruction (plan 12, decision 2): an
      # edge on its last cycle waits one more instruction. A second edge while one is pending keeps the first one's
      # cycle. The detector "polls the status of the NMI line during φ2 of each CPU cycle", so a line released within
      # the cycle it rose in leaves no edge: that is how a $2002 read or an NMI disable right after VBlank starts
      # suppresses the NMI. The IRQ line is polled without a cycle (plan 22 brings its timing).
      class InterruptLines
        # The poll sees edges up to the cycle before the previous instruction's last one.
        POLL_DELAY_CYCLES = 1

        def initialize(status:)
          @status = status
          @nmi_line = false
          @nmi_pending = false
          @nmi_edge_cycle = 0
          @irq_line = false
        end

        # The NMI line's new level, `true` while asserted, and the CPU cycle the change happened on.
        def nmi_line_changed(asserted, cycle)
          if asserted && !@nmi_line && !@nmi_pending
            @nmi_pending = true
            @nmi_edge_cycle = cycle
          elsif !asserted && @nmi_pending && @nmi_edge_cycle == cycle
            # Released before the φ2 sample of the cycle it rose in: the detector never saw it low.
            @nmi_pending = false
          end
          @nmi_line = asserted
        end

        attr_writer :irq_line

        # The vector of the interrupt a step starting on `cycle` takes, or nil, without taking it (for the tracer).
        def pending(cycle)
          if @nmi_pending && @nmi_edge_cycle < cycle - POLL_DELAY_CYCLES
            NMI_VECTOR
          elsif @irq_line && !@status.interrupt_disable?
            IRQ_VECTOR
          end
        end

        # The vector of the interrupt to take at the start of `cycle`, or nil. Taking an NMI clears it; an IRQ stays as
        # long as its line.
        def acknowledge(cycle)
          vector = pending(cycle)
          @nmi_pending = false if vector == NMI_VECTOR
          vector
        end

        # Reset forgets an NMI not yet taken (plan 07, decision 6); the lines keep the levels their devices set.
        def discard_pending_nmi
          @nmi_pending = false
        end
      end
    end
  end
end
