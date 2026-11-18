# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Register transfers (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. Every transfer sets
        # Z and N from the copied byte except TXS, which changes no flag.
        module Transfers
          # TAX
          def transfer_accumulator_to_index_x
            @index_x = @accumulator
            @status.update_zero_and_negative(@index_x)
          end

          # TAY
          def transfer_accumulator_to_index_y
            @index_y = @accumulator
            @status.update_zero_and_negative(@index_y)
          end

          # TXA
          def transfer_index_x_to_accumulator
            @accumulator = @index_x
            @status.update_zero_and_negative(@accumulator)
          end

          # TYA
          def transfer_index_y_to_accumulator
            @accumulator = @index_y
            @status.update_zero_and_negative(@accumulator)
          end

          # TSX
          def transfer_stack_pointer_to_index_x
            @index_x = @stack.pointer
            @status.update_zero_and_negative(@index_x)
          end

          # TXS
          def transfer_index_x_to_stack_pointer
            @stack.pointer = @index_x
          end
        end
      end
    end
  end
end
