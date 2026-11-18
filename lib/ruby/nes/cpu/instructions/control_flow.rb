# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # Jumps, subroutines, BRK and NOP (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. Each is
        # called with the program counter past the opcode and its operand.
        module ControlFlow
          # JMP, absolute or indirect: the addressing mode already resolved the target.
          def jump(target)
            @program_counter = target
          end

          # JSR: "the return address on the stack points 1 byte before the start of the next instruction".
          def jump_to_subroutine(target)
            @stack.push_word((@program_counter - 1) & Bits::WORD_MASK) # glossary: wrap-to-word
            @program_counter = target
          end

          # RTS: pulls the return address "and then increments the program counter".
          def return_from_subroutine
            @program_counter = (@stack.pull_word + 1) & Bits::WORD_MASK # glossary: wrap-to-word
          end

          # RTI: the flags (B and bit 5 dropped), then "the exact address of the next instruction".
          def return_from_interrupt
            @status.restore(@stack.pull)
            @program_counter = @stack.pull_word
          end

          # BRK ("Force Interrupt" in the Obelisk reference): "the return address that is pushed to the stack skips the
          # byte after the BRK opcode"; the flags go with B set, and I is "set to 1 after the old flags are pushed": the
          # interrupt sequence of Cpu::Interrupts, through the IRQ vector.
          def force_interrupt
            return_address = (@program_counter + 1) & Bits::WORD_MASK # glossary: wrap-to-word
            enter_interrupt(return_address, @status.byte_pushed_by_instruction, IRQ_VECTOR)
          end

          # NOP
          def no_operation; end
        end
      end
    end
  end
end
