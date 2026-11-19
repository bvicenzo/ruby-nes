# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      module Instructions
        # The seven unstable unofficial opcodes, included in Cpu, after "No More Secrets" (NMOS 6510 Unintended
        # Opcodes, V0.95, https://csdb.dk/release/?id=198357). On hardware their results depend on the chip, the
        # temperature and the RDY line (DMA); this is the documented behaviour without DMA, an approximation (plan 09,
        # decision 1). blargg's instr_test-v5 checks LAX #imm, SHX and SHY against a real NES (plan 12).
        module Unstable
          # "CONST is chip- and/or temperature dependent"; "For Emulation the best compromise [...] seems to be to use a
          # 'magic contant' of $EF in regular cycles" for ANE. For LAX #imm the document advises $EE, but blargg's
          # instr_test-v5 03-immediate, whose checksum comes from the console, passes only with $FF (plan 12).
          INDEX_X_AND_OPERAND_MAGIC_CONSTANT = 0xEF
          OPERAND_LOAD_MAGIC_CONSTANT = 0xFF

          # ANE (the wiki's XAA): "A = (A | {CONST}) & X & #{imm}". Z and N follow the result, as the Visual6502 wiki
          # says ("N and Z flags are set according to the result of XAA"); No More Secrets says they follow the
          # accumulator before the instruction instead.
          def and_index_x_and_operand(address)
            magic_accumulator = @accumulator | INDEX_X_AND_OPERAND_MAGIC_CONSTANT # glossary: bitwise-or
            @accumulator = magic_accumulator & @index_x & @bus.read(address) # glossary: bitwise-and
            @status.update_zero_and_negative(@accumulator)
          end

          # LAX #imm (LXA, ATX): "A,X = (A | {CONST}) & #{imm}"; Z and N follow the result, as ANE's: no document
          # states them, and instr_test-v5 03-immediate, which checks the flags, passes so (plan 12).
          def and_operand_into_accumulator_and_index_x(address)
            magic_accumulator = @accumulator | OPERAND_LOAD_MAGIC_CONSTANT # glossary: bitwise-or
            @accumulator = @index_x = magic_accumulator & @bus.read(address) # glossary: bitwise-and
            @status.update_zero_and_negative(@accumulator)
          end

          # SHA (the wiki's AHX), (indirect),Y and absolute,Y: "{addr} = A & X & {H+1}".
          def store_accumulator_and_index_x_and_high_byte(address)
            store_with_high_byte(@accumulator & @index_x, address, @index_y) # glossary: bitwise-and
          end

          # SHX, absolute,Y: "{addr} = X & {H+1}".
          def store_index_x_and_high_byte(address)
            store_with_high_byte(@index_x, address, @index_y)
          end

          # SHY, absolute,X: "{addr} = Y & {H+1}".
          def store_index_y_and_high_byte(address)
            store_with_high_byte(@index_y, address, @index_x)
          end

          # TAS (SHS), absolute,Y: "SP = A & X", then "{addr} = A & X & {H+1}".
          def transfer_and_store_stack_pointer(address)
            @stack.pointer = @accumulator & @index_x # glossary: bitwise-and
            store_with_high_byte(@stack.pointer, address, @index_y)
          end

          # LAS (LAR), absolute,Y: "A,X,SP = {addr} & SP"; "N and Z are set as expected by a load instruction".
          def load_accumulator_index_x_and_stack_pointer(address)
            @accumulator = @index_x = @stack.pointer = @bus.read(address) & @stack.pointer # glossary: bitwise-and
            @status.update_zero_and_negative(@accumulator)
          end

          private

          # Writes `value` ANDed with H + 1, H being "the high byte of the target address of the argument" (before the
          # index). When the index crossed a page, "the highbyte of the target address is incremented by one (as
          # expected), and then ANDed with" the value, which is the byte written: it lands on the page it names.
          def store_with_high_byte(value, address, index)
            base = (address - index) & Bits::WORD_MASK # glossary: wrap-to-word
            stored = value & ((base >> 8) + 1) & Bits::BYTE_MASK # glossary: high-byte, wrap-to-byte, bitwise-and
            target = address
            if (base & Bits::PAGE_MASK) != (address & Bits::PAGE_MASK) # glossary: page-crossed
              target = (stored << 8) | (address & Bits::BYTE_MASK) # glossary: combine-bytes, low-byte
            end
            @bus.write(target, stored)
          end
        end
      end
    end
  end
end
