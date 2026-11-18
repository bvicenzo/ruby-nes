# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Stack instructions (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. PHP pushes P with B
        # and bit 5 set; PLP drops them (Status#restore); PLA sets Z and N.
        module StackOperations
          # PHA
          def push_accumulator
            @stack.push(@accumulator)
          end

          # PHP
          def push_status
            @stack.push(@status.byte_pushed_by_instruction)
          end

          # PLA
          def pull_accumulator
            @accumulator = @stack.pull
            @status.update_zero_and_negative(@accumulator)
          end

          # PLP. The one-instruction delay of a change to I on IRQ polling belongs to plan 07.
          def pull_status
            @status.restore(@stack.pull)
          end
        end
      end
    end
  end
end
