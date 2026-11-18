# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Branches (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. Each is given the target
        # Cpu#relative_address resolved and takes it when its flag is in the stated state. A branch costs "2 (3 if
        # branch taken, 4 if page crossed)": Cpu#step charges the base 2, take_branch the extra cycles.
        module Branches
          # BCC
          def branch_if_carry_clear(target)
            take_branch(target) unless @status.carry?
          end

          # BCS
          def branch_if_carry_set(target)
            take_branch(target) if @status.carry?
          end

          # BEQ
          def branch_if_equal(target)
            take_branch(target) if @status.zero?
          end

          # BNE
          def branch_if_not_equal(target)
            take_branch(target) unless @status.zero?
          end

          # BMI
          def branch_if_minus(target)
            take_branch(target) if @status.negative?
          end

          # BPL
          def branch_if_plus(target)
            take_branch(target) unless @status.negative?
          end

          # BVC
          def branch_if_overflow_clear(target)
            take_branch(target) unless @status.overflow?
          end

          # BVS
          def branch_if_overflow_set(target)
            take_branch(target) if @status.overflow?
          end

          # Moves the program counter (already past the operand) to the target: one cycle, and one more when the
          # target is on another page.
          def take_branch(target)
            @cycles += 1
            @cycles += 1 if (@program_counter & Bits::PAGE_MASK) != (target & Bits::PAGE_MASK) # glossary: page-crossed
            @program_counter = target
          end
        end
      end
    end
  end
end
