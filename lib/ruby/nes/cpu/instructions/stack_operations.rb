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

          # PLP. It changes "the I flag after polling for interrupts" (https://www.nesdev.org/wiki/CPU_interrupts): the
          # poll that follows it sees I as it was before (plan 22, decision 1).
          def pull_status
            @interrupt_lines.poll_with_interrupt_disable(@status.interrupt_disable?)
            @status.restore(@stack.pull)
          end
        end
      end
    end
  end
end
