# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Flag instructions (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu: each changes one flag.
        # The one-instruction delay of CLI and SEI on IRQ polling belongs to plan 07.
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
            @status.interrupt_disable = true
          end
        end
      end
    end
  end
end
