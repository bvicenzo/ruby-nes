# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # ASL, LSR, ROL and ROR (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. The Shifter
        # computes the byte and the flags; these methods only take the byte from, and put it back into, the accumulator
        # or memory, where the original byte is written back before the result (Cpu#write_modified).
        module Shifts
          # ASL A
          def shift_left_accumulator
            @accumulator = @shifter.shift_left(@accumulator)
          end

          # ASL with a memory operand
          def shift_left_memory(address)
            original = @bus.read(address)
            write_modified(address, original, @shifter.shift_left(original))
          end

          # LSR A
          def shift_right_accumulator
            @accumulator = @shifter.shift_right(@accumulator)
          end

          # LSR with a memory operand
          def shift_right_memory(address)
            original = @bus.read(address)
            write_modified(address, original, @shifter.shift_right(original))
          end

          # ROL A
          def rotate_left_accumulator
            @accumulator = @shifter.rotate_left(@accumulator)
          end

          # ROL with a memory operand
          def rotate_left_memory(address)
            original = @bus.read(address)
            write_modified(address, original, @shifter.rotate_left(original))
          end

          # ROR A
          def rotate_right_accumulator
            @accumulator = @shifter.rotate_right(@accumulator)
          end

          # ROR with a memory operand
          def rotate_right_memory(address)
            original = @bus.read(address)
            write_modified(address, original, @shifter.rotate_right(original))
          end
        end
      end
    end
  end
end
