# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Comparisons (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. A subtraction whose result
        # is only seen in the flags: C is "register >= memory", Z is "register == memory", N is bit 7 of the
        # difference; "comparison does _not_ affect overflow".
        module Comparisons
          # CMP
          def compare_with_accumulator(address)
            compare(@accumulator, @bus.read(address))
          end

          # CPX
          def compare_with_index_x(address)
            compare(@index_x, @bus.read(address))
          end

          # CPY
          def compare_with_index_y(address)
            compare(@index_y, @bus.read(address))
          end

          private

          def compare(register, operand)
            @status.carry = register >= operand
            @status.update_zero_and_negative((register - operand) & Bits::BYTE_MASK) # glossary: wrap-to-byte
          end
        end
      end
    end
  end
end
