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
      class InterruptLines
        def initialize(status:)
          @status = status
          @nmi_line = false
          @nmi_pending = false
          @irq_line = false
        end

        def nmi_line=(asserted)
          @nmi_pending = true if asserted && !@nmi_line
          @nmi_line = asserted
        end

        attr_writer :irq_line

        # The vector of the interrupt to take now, or nil. Taking an NMI clears it; an IRQ stays as long as its line.
        def acknowledge
          if @nmi_pending
            @nmi_pending = false
            NMI_VECTOR
          elsif @irq_line && !@status.interrupt_disable?
            IRQ_VECTOR
          end
        end

        # Reset forgets an NMI not yet taken (plan 07, decision 6); the lines keep the levels their devices set.
        def discard_pending_nmi
          @nmi_pending = false
        end
      end
    end
  end
end
