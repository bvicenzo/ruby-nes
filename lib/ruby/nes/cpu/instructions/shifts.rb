# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # ASL, LSR, ROL and ROR (https://www.nesdev.org/wiki/Instruction_reference), included in Cpu. The Shifter
        # computes the byte and the flags; these methods only take the byte from, and put it back into, the accumulator
        # or memory. The read-modify-write double write is not modelled (plan 06, decision 5).
        module Shifts
          # ASL A
          def shift_left_accumulator
            @accumulator = @shifter.shift_left(@accumulator)
          end

          # ASL with a memory operand
          def shift_left_memory(address)
            @bus.write(address, @shifter.shift_left(@bus.read(address)))
          end

          # LSR A
          def shift_right_accumulator
            @accumulator = @shifter.shift_right(@accumulator)
          end

          # LSR with a memory operand
          def shift_right_memory(address)
            @bus.write(address, @shifter.shift_right(@bus.read(address)))
          end

          # ROL A
          def rotate_left_accumulator
            @accumulator = @shifter.rotate_left(@accumulator)
          end

          # ROL with a memory operand
          def rotate_left_memory(address)
            @bus.write(address, @shifter.rotate_left(@bus.read(address)))
          end

          # ROR A
          def rotate_right_accumulator
            @accumulator = @shifter.rotate_right(@accumulator)
          end

          # ROR with a memory operand
          def rotate_right_memory(address)
            @bus.write(address, @shifter.rotate_right(@bus.read(address)))
          end
        end
      end
    end
  end
end
