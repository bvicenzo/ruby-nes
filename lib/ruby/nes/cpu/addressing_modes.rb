# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # One resolver per 6502 addressing mode (https://www.nesdev.org/wiki/CPU_addressing_modes), included in Cpu. Each
      # is called with the program counter on the operand (the opcode already fetched), fetches the operand, leaves the
      # program counter past it and returns the effective address. Implied and accumulator modes have nothing to
      # resolve.
      #
      # Indexed reads cost one more cycle when the index carries into the next page ("+ means add a cycle for write
      # instructions or for page wrapping on read instructions"): the `_for_read` resolvers add it to `cycles`; write and
      # read-modify-write instructions use the plain ones, whose extra cycle is part of their base count (plan 05,
      # decision 2).
      #
      # Both read the address whose high byte is not fixed yet, as the 6502 does
      # (https://www.nesdev.org/6502_cpu.txt, plan 12, decision 4): "The high byte of the effective address may be
      # invalid at this time, i.e. it may be smaller by $100". The `_for_read` resolvers only when the index crosses a
      # page ("This cycle will be executed only if the effective address was invalid"); the plain ones always,
      # "Because the processor cannot undo a write to an invalid address, it always reads from the address first".
      # The other dummy reads (zero page indexed, implied, the stack) never reach a register and stay unmodelled.
      module AddressingModes
        def immediate_address
          address = @program_counter
          @program_counter = (@program_counter + 1) & Bits::WORD_MASK # glossary: wrap-to-word
          address
        end

        def zero_page_address = fetch_byte

        # Zero page indexed: `PEEK((arg + X) % 256)`, it never leaves page zero.
        def zero_page_x_address
          (fetch_byte + @index_x) & Bits::BYTE_MASK # glossary: wrap-to-byte
        end

        def zero_page_y_address
          (fetch_byte + @index_y) & Bits::BYTE_MASK # glossary: wrap-to-byte
        end

        def absolute_address = fetch_word

        def absolute_x_address = indexed_for_write(fetch_word, @index_x)

        def absolute_x_address_for_read = indexed_for_read(fetch_word, @index_x)

        def absolute_y_address = indexed_for_write(fetch_word, @index_y)

        def absolute_y_address_for_read = indexed_for_read(fetch_word, @index_y)

        # JMP only. The pointer's high byte comes from the same page: "JMP ($03FF) reads $03FF and $0300 instead of
        # $0400" (https://www.nesdev.org/wiki/Instruction_reference).
        def indirect_address = word_within_page(fetch_word)

        # `($nn,X)`: the pointer is `(arg + X) % 256`, and both of its bytes stay in page zero.
        def indexed_indirect_address
          word_within_page((fetch_byte + @index_x) & Bits::BYTE_MASK) # glossary: wrap-to-byte
        end

        # `($nn),Y`: the base is read from page zero at `arg` and `(arg + 1) % 256`, then Y is added.
        def indirect_indexed_address = indexed_for_write(word_within_page(fetch_byte), @index_y)

        def indirect_indexed_address_for_read = indexed_for_read(word_within_page(fetch_byte), @index_y)

        # The branch target: a signed offset "relative to the first byte after the branch instruction". The program
        # counter only moves past the offset; taking the branch is the instruction's decision.
        def relative_address
          offset = fetch_byte
          signed_offset = offset >= Bits::SIGN_BIT ? offset - Bits::BYTE_RANGE : offset # glossary: signed-byte
          (@program_counter + signed_offset) & Bits::WORD_MASK # glossary: wrap-to-word
        end

        private

        # The little-endian word at `pointer`, its high byte read without carrying into the next page. For a pointer in
        # page zero this is the `(arg + 1) % 256` of the indirect modes.
        def word_within_page(pointer)
          low = @bus.read(pointer)
          page = pointer & Bits::PAGE_MASK # glossary: increment-within-page
          high = @bus.read(page | ((pointer + 1) & Bits::BYTE_MASK)) # glossary: increment-within-page
          (high << 8) | low # glossary: combine-bytes
        end

        # A read pays the page-cross cycle, and only then the dummy read at the address whose high byte is not fixed.
        def indexed_for_read(base, index)
          address = (base + index) & Bits::WORD_MASK # glossary: wrap-to-word
          if (base & Bits::PAGE_MASK) != (address & Bits::PAGE_MASK) # glossary: page-crossed
            @cycles += 1
            @bus.read((base & Bits::PAGE_MASK) | (address & Bits::BYTE_MASK)) # glossary: add-within-page
          end
          address
        end

        # Writes and read-modify-write instructions always make the dummy read at the address whose high byte is not
        # fixed (the effective address itself when the index stays in the page).
        def indexed_for_write(base, index)
          address = (base + index) & Bits::WORD_MASK # glossary: wrap-to-word
          @bus.read((base & Bits::PAGE_MASK) | (address & Bits::BYTE_MASK)) # glossary: add-within-page
          address
        end
      end
    end
  end
end
