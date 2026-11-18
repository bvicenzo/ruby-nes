# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Arithmetic (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. Binary only: decimal mode "is
        # permanently disabled on the NES' 2A03 CPU", although the D flag can still be set and read.
        module Arithmetic
          # ADC
          def add_with_carry(address)
            add_to_accumulator(@bus.read(address))
          end

          # SBC: "SBC subtracts 1 more when carry is _clear_", which is ADC with the operand inverted.
          def subtract_with_carry(address)
            add_to_accumulator(@bus.read(address) ^ Bits::BYTE_MASK) # glossary: invert-byte
          end

          private

          # A + operand + C. C is the carry out of bit 7; V is set when the result's sign differs from the signs of
          # both addends.
          def add_to_accumulator(operand)
            sum = @accumulator + operand + (@status.carry? ? 1 : 0)
            result = sum & Bits::BYTE_MASK # glossary: wrap-to-byte
            @status.carry = sum > Bits::BYTE_MASK
            sign_flips = (result ^ @accumulator) & (result ^ operand) # glossary: signed-overflow
            @status.overflow = sign_flips.anybits?(Bits::SIGN_BIT)
            @accumulator = result
            @status.update_zero_and_negative(result)
          end
        end
      end
    end
  end
end
