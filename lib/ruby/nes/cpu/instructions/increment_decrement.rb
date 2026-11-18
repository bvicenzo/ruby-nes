# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Increments and decrements (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. One up or
        # down, wrapping within a byte; Z and N from the result, C and V untouched. The read-modify-write double write
        # of INC and DEC is not modelled (plan 06, decision 5).
        module IncrementDecrement
          # INC
          def increment_memory(address)
            result = (@bus.read(address) + 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
            @bus.write(address, result)
            @status.update_zero_and_negative(result)
          end

          # DEC
          def decrement_memory(address)
            result = (@bus.read(address) - 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
            @bus.write(address, result)
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
