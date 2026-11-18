# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # The hardware stack (https://www.nesdev.org/wiki/Stack): page $0100-$01FF, descending and empty, so a push
      # stores at $0100 + S and then decrements S, and a pull increments S and then reads. S is byte-wide
      # (https://www.nesdev.org/wiki/CPU_registers) and wraps both ways. Words go high byte first, as JSR pushes its
      # return address (https://www.nesdev.org/wiki/Instruction_reference).
      class Stack
        STACK_PAGE_START = 0x0100

        # The stack pointer, S.
        attr_accessor :pointer

        def initialize(bus:, pointer: 0)
          @bus = bus
          @pointer = pointer
        end

        def push(value)
          @bus.write(STACK_PAGE_START + @pointer, value)
          @pointer = (@pointer - 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
        end

        def pull
          @pointer = (@pointer + 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
          @bus.read(STACK_PAGE_START + @pointer)
        end

        def push_word(word)
          push(word >> 8) # glossary: high-byte
          push(word & Bits::BYTE_MASK) # glossary: low-byte
        end

        def pull_word
          low = pull
          high = pull
          (high << 8) | low # glossary: combine-bytes
        end
      end
    end
  end
end
