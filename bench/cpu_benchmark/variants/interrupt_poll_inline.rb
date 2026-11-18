# frozen_string_literal: true

# Variant for decision 13 of docs/architecture.md: the interrupt poll inlined in Cpu#step. The CPU keeps the NMI edge
# and the IRQ level in its own ivars, so a step with nothing pending reads two ivars instead of calling
# InterruptLines#acknowledge. Same rules: the NMI is taken on the released-to-asserted edge and stays pending until
# taken, the IRQ is masked by I, the NMI wins, and reset discards a pending NMI.
module Ruby
  module Nes
    class Cpu
      # Adds the line ivars after the original constructor and discards a pending NMI on reset.
      module InlineInterruptLines
        def initialize(...)
          super
          @nmi_line = false
          @nmi_pending = false
          @irq_line = false
        end

        def reset
          @nmi_pending = false
          super
        end
      end

      prepend InlineInterruptLines

      def nmi_line=(asserted)
        @nmi_pending = true if asserted && !@nmi_line
        @nmi_line = asserted
      end

      attr_writer :irq_line

      def step
        return stay_jammed if @jammed

        cycles_before = @cycles
        if @nmi_pending
          @nmi_pending = false
          take_interrupt(NMI_VECTOR)
        elsif @irq_line && !@status.interrupt_disable?
          take_interrupt(IRQ_VECTOR)
        else
          opcode = fetch_byte
          execute(opcode)
          @cycles += Opcodes::TABLE[opcode].cycles
        end
        @cycles - cycles_before
      end
    end
  end
end
