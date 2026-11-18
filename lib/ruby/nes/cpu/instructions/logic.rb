# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Logic instructions (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. AND, EOR and ORA
        # keep their result in A and set Z and N from it.
        module Logic
          # AND
          def and_with_accumulator(address)
            @accumulator &= @bus.read(address) # glossary: bitwise-and
            @status.update_zero_and_negative(@accumulator)
          end

          # EOR
          def exclusive_or_with_accumulator(address)
            @accumulator ^= @bus.read(address) # glossary: bitwise-exclusive-or
            @status.update_zero_and_negative(@accumulator)
          end

          # ORA
          def or_with_accumulator(address)
            @accumulator |= @bus.read(address) # glossary: bitwise-or
            @status.update_zero_and_negative(@accumulator)
          end

          # BIT: Z from A AND memory; "Bits 7 and 6 of the memory value are loaded directly into the negative and
          # overflow flags", which sit at the same positions in P. A is not changed.
          def test_bits(address)
            operand = @bus.read(address)
            @status.zero = @accumulator.nobits?(operand)
            @status.negative = operand.anybits?(Status::NEGATIVE_FLAG)
            @status.overflow = operand.anybits?(Status::OVERFLOW_FLAG)
          end
        end
      end
    end
  end
end
