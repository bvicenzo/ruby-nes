# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Flag instructions (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu: each changes one flag.
        # CLI and SEI "change the I flag after polling for interrupts" (https://www.nesdev.org/wiki/CPU_interrupts): the
        # poll that follows them sees I as it was before (plan 22, decision 1).
        module Flags
          # CLC
          def clear_carry
            @status.carry = false
          end

          # CLD
          def clear_decimal
            @status.decimal = false
          end

          # CLI
          def clear_interrupt_disable
            @interrupt_lines.poll_with_interrupt_disable(@status.interrupt_disable?)
            @status.interrupt_disable = false
          end

          # CLV
          def clear_overflow
            @status.overflow = false
          end

          # SEC
          def set_carry
            @status.carry = true
          end

          # SED
          def set_decimal
            @status.decimal = true
          end

          # SEI
          def set_interrupt_disable
            @interrupt_lines.poll_with_interrupt_disable(@status.interrupt_disable?)
            @status.interrupt_disable = true
          end
        end
      end
    end
  end
end
