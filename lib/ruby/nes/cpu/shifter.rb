# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # The shift and rotate unit behind ASL, LSR, ROL and ROR (https://www.nesdev.org/wiki/Instruction_reference).
      # Each operation takes a byte, returns the shifted byte and sets C (the bit shifted out), Z and N in the Status
      # it was built with; the instruction decides where the byte came from and where it goes (plan 06).
      class Shifter
        # Bit 0: shifted out to C by LSR and ROR, and where ROL shifts the old C in.
        LOWEST_BIT = 0x01

        def initialize(status:)
          @status = status
        end

        # ASL: a 0 enters bit 0.
        def shift_left(value)
          @status.carry = (value & Bits::SIGN_BIT) != 0 # glossary: flag-set
          with_zero_and_negative((value << 1) & Bits::BYTE_MASK) # glossary: shift-left, wrap-to-byte
        end

        # LSR: a 0 enters bit 7, so N is always cleared.
        def shift_right(value)
          @status.carry = (value & LOWEST_BIT) != 0 # glossary: flag-set
          with_zero_and_negative(value >> 1) # glossary: shift-right
        end

        # ROL: the old C enters bit 0.
        def rotate_left(value)
          carry_in = @status.carry? ? LOWEST_BIT : 0
          @status.carry = (value & Bits::SIGN_BIT) != 0 # glossary: flag-set
          shifted = (value << 1) & Bits::BYTE_MASK # glossary: shift-left, wrap-to-byte
          with_zero_and_negative(shifted | carry_in) # glossary: bitwise-or
        end

        # ROR: the old C enters bit 7.
        def rotate_right(value)
          carry_in = @status.carry? ? Bits::SIGN_BIT : 0
          @status.carry = (value & LOWEST_BIT) != 0 # glossary: flag-set
          with_zero_and_negative((value >> 1) | carry_in) # glossary: shift-right, bitwise-or
        end

        private

        def with_zero_and_negative(result)
          @status.update_zero_and_negative(result)
          result
        end
      end
    end
  end
end
