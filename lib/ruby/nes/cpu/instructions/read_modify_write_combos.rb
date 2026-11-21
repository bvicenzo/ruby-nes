# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # The unofficial read-modify-write combos (https://www.nesdev.org/wiki/Programming_with_unofficial_opcodes),
        # included in Cpu. Each is "Equivalent to" a memory instruction "then" an accumulator instruction: the byte is
        # read once, modified, written back, and the modified byte feeds the second instruction, whose flags are the
        # ones left (C comes from the shift or rotation unless ADC, SBC or CMP sets it). The original byte is
        # written back before the modified one (Cpu#write_modified), as for every read-modify-write instruction.
        module ReadModifyWriteCombos
          # SLO: ASL then ORA.
          def shift_left_then_or(address)
            original = @bus.read(address)
            shifted = write_modified(address, original, @shifter.shift_left(original))
            @accumulator |= shifted # glossary: bitwise-or
            @status.update_zero_and_negative(@accumulator)
          end

          # RLA: ROL then AND.
          def rotate_left_then_and(address)
            original = @bus.read(address)
            rotated = write_modified(address, original, @shifter.rotate_left(original))
            @accumulator &= rotated # glossary: bitwise-and
            @status.update_zero_and_negative(@accumulator)
          end

          # SRE: LSR then EOR.
          def shift_right_then_exclusive_or(address)
            original = @bus.read(address)
            shifted = write_modified(address, original, @shifter.shift_right(original))
            @accumulator ^= shifted # glossary: bitwise-exclusive-or
            @status.update_zero_and_negative(@accumulator)
          end

          # RRA: ROR then ADC, so the bit rotated out is ADC's carry in: "A + value / 2, where value is 9-bit".
          def rotate_right_then_add(address)
            original = @bus.read(address)
            rotated = write_modified(address, original, @shifter.rotate_right(original))
            add_to_accumulator(rotated)
          end

          # DCP: DEC then CMP.
          def decrement_then_compare(address)
            original = @bus.read(address)
            decremented = write_modified(address, original, (original - 1) & Bits::BYTE_MASK) # glossary: wrap-to-byte
            compare(@accumulator, decremented)
          end

          # ISB (the wiki's ISC): INC then SBC, which is ADC with the operand inverted.
          def increment_then_subtract(address)
            original = @bus.read(address)
            incremented = write_modified(address, original, (original + 1) & Bits::BYTE_MASK) # glossary: wrap-to-byte
            add_to_accumulator(incremented ^ Bits::BYTE_MASK) # glossary: invert-byte
          end
        end
      end
    end
  end
end
