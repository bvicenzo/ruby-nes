# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # The unofficial immediate combos (https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes), included in
        # Cpu: an AND with the operand (Logic#and_with_accumulator), then a second step on the result. Each takes the
        # operand's address, as the immediate addressing mode resolves it, and reads it once.
        module ImmediateCombos
          # ARR's result decides C and V: "C is bit 6 and V is bit 6 xor bit 5"
          # (https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes).
          CARRY_SOURCE_BIT = 0x40
          OVERFLOW_PARTNER_BIT = 0x20

          # ANC: "Does AND #i, setting N and Z flags based on the result. Then it copies N (bit 7) to C."
          def and_then_copy_sign_to_carry(address)
            and_with_accumulator(address)
            @status.carry = @accumulator.anybits?(Bits::SIGN_BIT)
          end

          # ALR: "Equivalent to AND #i then LSR A."
          def and_then_shift_right(address)
            and_with_accumulator(address)
            shift_right_accumulator
          end

          # ARR: "Similar to AND #i then ROR A, except sets the flags differently. N and Z are normal, but C is bit 6 and
          # V is bit 6 xor bit 5."
          def and_then_rotate_right(address)
            and_with_accumulator(address)
            rotate_right_accumulator
            @status.carry = @accumulator.anybits?(CARRY_SOURCE_BIT)
            @status.overflow = @accumulator.anybits?(CARRY_SOURCE_BIT) != @accumulator.anybits?(OVERFLOW_PARTNER_BIT)
          end

          # AXS: "Sets X to {(A AND X) - #value without borrow}, and updates NZC": C, Z and N as CMP sets them, and "it
          # does not affect the V flag" (https://www.nesdev.org/6502_cpu.txt).
          def and_index_x_then_subtract(address)
            combined = @accumulator & @index_x # glossary: bitwise-and
            operand = @bus.read(address)
            compare(combined, operand)
            @index_x = (combined - operand) & Bits::BYTE_MASK # glossary: wrap-to-byte
          end
        end
      end
    end
  end
end
