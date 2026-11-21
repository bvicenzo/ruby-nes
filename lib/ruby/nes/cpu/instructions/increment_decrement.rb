# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Increments and decrements (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. One up or
        # down, wrapping within a byte; Z and N from the result, C and V untouched. INC and DEC write the original byte
        # back before the result (Cpu#write_modified).
        module IncrementDecrement
          # INC
          def increment_memory(address)
            original = @bus.read(address)
            result = write_modified(address, original, (original + 1) & Bits::BYTE_MASK) # glossary: wrap-to-byte
            @status.update_zero_and_negative(result)
          end

          # DEC
          def decrement_memory(address)
            original = @bus.read(address)
            result = write_modified(address, original, (original - 1) & Bits::BYTE_MASK) # glossary: wrap-to-byte
            @status.update_zero_and_negative(result)
          end

          # INX
          def increment_index_x
            @index_x = (@index_x + 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
            @status.update_zero_and_negative(@index_x)
          end

          # INY
          def increment_index_y
            @index_y = (@index_y + 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
            @status.update_zero_and_negative(@index_y)
          end

          # DEX
          def decrement_index_x
            @index_x = (@index_x - 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
            @status.update_zero_and_negative(@index_x)
          end

          # DEY
          def decrement_index_y
            @index_y = (@index_y - 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
            @status.update_zero_and_negative(@index_y)
          end
        end
      end
    end
  end
end
