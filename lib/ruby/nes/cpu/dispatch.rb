# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # The opcode dispatch, included in Cpu: one `when` per official opcode
      # (https://www.nesdev.org/wiki/Instruction_reference), naming the instruction and the addressing mode resolver
      # that feeds it. Indexed reads use the `_for_read` resolvers, which charge the page-cross cycle; stores and
      # read-modify-write instructions use the plain ones (plan 05, decision 2).
      module Dispatch
        private

        # A conscious exception to the Metrics cops (plan 06, decision 1; docs/architecture.md, Decisions log): Ruby
        # compiles a `case` whose `when`s are integer literals into `opt_case_dispatch`, a single hash lookup, with no
        # Proc#call or `send` per instruction. That is the shape YJIT and ZJIT compile best and Spinel can type, and it
        # keeps the whole opcode map readable in one place. Plan 10 measures it against a table of lambdas.
        # rubocop:disable-next Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
        def execute(opcode)
          case opcode
          when 0x00 then force_interrupt # BRK
          when 0x01 then or_with_accumulator(indexed_indirect_address) # ORA (indirect,X)
          when 0x05 then or_with_accumulator(zero_page_address) # ORA zero page
          when 0x06 then shift_left_memory(zero_page_address) # ASL zero page
          when 0x08 then push_status # PHP
          when 0x09 then or_with_accumulator(immediate_address) # ORA #immediate
          when 0x0A then shift_left_accumulator # ASL accumulator
          when 0x0D then or_with_accumulator(absolute_address) # ORA absolute
          when 0x0E then shift_left_memory(absolute_address) # ASL absolute
          when 0x10 then branch_if_plus(relative_address) # BPL relative
          when 0x11 then or_with_accumulator(indirect_indexed_address_for_read) # ORA (indirect),Y
          when 0x15 then or_with_accumulator(zero_page_x_address) # ORA zero page,X
          when 0x16 then shift_left_memory(zero_page_x_address) # ASL zero page,X
          when 0x18 then clear_carry # CLC
          when 0x19 then or_with_accumulator(absolute_y_address_for_read) # ORA absolute,Y
          when 0x1D then or_with_accumulator(absolute_x_address_for_read) # ORA absolute,X
          when 0x1E then shift_left_memory(absolute_x_address) # ASL absolute,X
          when 0x20 then jump_to_subroutine(absolute_address) # JSR absolute
          when 0x21 then and_with_accumulator(indexed_indirect_address) # AND (indirect,X)
          when 0x24 then test_bits(zero_page_address) # BIT zero page
          when 0x25 then and_with_accumulator(zero_page_address) # AND zero page
          when 0x26 then rotate_left_memory(zero_page_address) # ROL zero page
          when 0x28 then pull_status # PLP
          when 0x29 then and_with_accumulator(immediate_address) # AND #immediate
          when 0x2A then rotate_left_accumulator # ROL accumulator
          when 0x2C then test_bits(absolute_address) # BIT absolute
          when 0x2D then and_with_accumulator(absolute_address) # AND absolute
          when 0x2E then rotate_left_memory(absolute_address) # ROL absolute
          when 0x30 then branch_if_minus(relative_address) # BMI relative
          when 0x31 then and_with_accumulator(indirect_indexed_address_for_read) # AND (indirect),Y
          when 0x35 then and_with_accumulator(zero_page_x_address) # AND zero page,X
          when 0x36 then rotate_left_memory(zero_page_x_address) # ROL zero page,X
          when 0x38 then set_carry # SEC
          when 0x39 then and_with_accumulator(absolute_y_address_for_read) # AND absolute,Y
          when 0x3D then and_with_accumulator(absolute_x_address_for_read) # AND absolute,X
          when 0x3E then rotate_left_memory(absolute_x_address) # ROL absolute,X
          when 0x40 then return_from_interrupt # RTI
          when 0x41 then exclusive_or_with_accumulator(indexed_indirect_address) # EOR (indirect,X)
          when 0x45 then exclusive_or_with_accumulator(zero_page_address) # EOR zero page
          when 0x46 then shift_right_memory(zero_page_address) # LSR zero page
          when 0x48 then push_accumulator # PHA
          when 0x49 then exclusive_or_with_accumulator(immediate_address) # EOR #immediate
          when 0x4A then shift_right_accumulator # LSR accumulator
          when 0x4C then jump(absolute_address) # JMP absolute
          when 0x4D then exclusive_or_with_accumulator(absolute_address) # EOR absolute
          when 0x4E then shift_right_memory(absolute_address) # LSR absolute
          when 0x50 then branch_if_overflow_clear(relative_address) # BVC relative
          when 0x51 then exclusive_or_with_accumulator(indirect_indexed_address_for_read) # EOR (indirect),Y
          when 0x55 then exclusive_or_with_accumulator(zero_page_x_address) # EOR zero page,X
          when 0x56 then shift_right_memory(zero_page_x_address) # LSR zero page,X
          when 0x58 then clear_interrupt_disable # CLI
          when 0x59 then exclusive_or_with_accumulator(absolute_y_address_for_read) # EOR absolute,Y
          when 0x5D then exclusive_or_with_accumulator(absolute_x_address_for_read) # EOR absolute,X
          when 0x5E then shift_right_memory(absolute_x_address) # LSR absolute,X
          when 0x60 then return_from_subroutine # RTS
          when 0x61 then add_with_carry(indexed_indirect_address) # ADC (indirect,X)
          when 0x65 then add_with_carry(zero_page_address) # ADC zero page
          when 0x66 then rotate_right_memory(zero_page_address) # ROR zero page
          when 0x68 then pull_accumulator # PLA
          when 0x69 then add_with_carry(immediate_address) # ADC #immediate
          when 0x6A then rotate_right_accumulator # ROR accumulator
          when 0x6C then jump(indirect_address) # JMP indirect
          when 0x6D then add_with_carry(absolute_address) # ADC absolute
          when 0x6E then rotate_right_memory(absolute_address) # ROR absolute
          when 0x70 then branch_if_overflow_set(relative_address) # BVS relative
          when 0x71 then add_with_carry(indirect_indexed_address_for_read) # ADC (indirect),Y
          when 0x75 then add_with_carry(zero_page_x_address) # ADC zero page,X
          when 0x76 then rotate_right_memory(zero_page_x_address) # ROR zero page,X
          when 0x78 then set_interrupt_disable # SEI
          when 0x79 then add_with_carry(absolute_y_address_for_read) # ADC absolute,Y
          when 0x7D then add_with_carry(absolute_x_address_for_read) # ADC absolute,X
          when 0x7E then rotate_right_memory(absolute_x_address) # ROR absolute,X
          when 0x81 then store_accumulator(indexed_indirect_address) # STA (indirect,X)
          when 0x84 then store_index_y(zero_page_address) # STY zero page
          when 0x85 then store_accumulator(zero_page_address) # STA zero page
          when 0x86 then store_index_x(zero_page_address) # STX zero page
          when 0x88 then decrement_index_y # DEY
          when 0x8A then transfer_index_x_to_accumulator # TXA
          when 0x8C then store_index_y(absolute_address) # STY absolute
          when 0x8D then store_accumulator(absolute_address) # STA absolute
          when 0x8E then store_index_x(absolute_address) # STX absolute
          when 0x90 then branch_if_carry_clear(relative_address) # BCC relative
          when 0x91 then store_accumulator(indirect_indexed_address) # STA (indirect),Y
          when 0x94 then store_index_y(zero_page_x_address) # STY zero page,X
          when 0x95 then store_accumulator(zero_page_x_address) # STA zero page,X
          when 0x96 then store_index_x(zero_page_y_address) # STX zero page,Y
          when 0x98 then transfer_index_y_to_accumulator # TYA
          when 0x99 then store_accumulator(absolute_y_address) # STA absolute,Y
          when 0x9A then transfer_index_x_to_stack_pointer # TXS
          when 0x9D then store_accumulator(absolute_x_address) # STA absolute,X
          when 0xA0 then load_index_y(immediate_address) # LDY #immediate
          when 0xA1 then load_accumulator(indexed_indirect_address) # LDA (indirect,X)
          when 0xA2 then load_index_x(immediate_address) # LDX #immediate
          when 0xA4 then load_index_y(zero_page_address) # LDY zero page
          when 0xA5 then load_accumulator(zero_page_address) # LDA zero page
          when 0xA6 then load_index_x(zero_page_address) # LDX zero page
          when 0xA8 then transfer_accumulator_to_index_y # TAY
          when 0xA9 then load_accumulator(immediate_address) # LDA #immediate
          when 0xAA then transfer_accumulator_to_index_x # TAX
          when 0xAC then load_index_y(absolute_address) # LDY absolute
          when 0xAD then load_accumulator(absolute_address) # LDA absolute
          when 0xAE then load_index_x(absolute_address) # LDX absolute
          when 0xB0 then branch_if_carry_set(relative_address) # BCS relative
          when 0xB1 then load_accumulator(indirect_indexed_address_for_read) # LDA (indirect),Y
          when 0xB4 then load_index_y(zero_page_x_address) # LDY zero page,X
          when 0xB5 then load_accumulator(zero_page_x_address) # LDA zero page,X
          when 0xB6 then load_index_x(zero_page_y_address) # LDX zero page,Y
          when 0xB8 then clear_overflow # CLV
          when 0xB9 then load_accumulator(absolute_y_address_for_read) # LDA absolute,Y
          when 0xBA then transfer_stack_pointer_to_index_x # TSX
          when 0xBC then load_index_y(absolute_x_address_for_read) # LDY absolute,X
          when 0xBD then load_accumulator(absolute_x_address_for_read) # LDA absolute,X
          when 0xBE then load_index_x(absolute_y_address_for_read) # LDX absolute,Y
          when 0xC0 then compare_with_index_y(immediate_address) # CPY #immediate
          when 0xC1 then compare_with_accumulator(indexed_indirect_address) # CMP (indirect,X)
          when 0xC4 then compare_with_index_y(zero_page_address) # CPY zero page
          when 0xC5 then compare_with_accumulator(zero_page_address) # CMP zero page
          when 0xC6 then decrement_memory(zero_page_address) # DEC zero page
          when 0xC8 then increment_index_y # INY
          when 0xC9 then compare_with_accumulator(immediate_address) # CMP #immediate
          when 0xCA then decrement_index_x # DEX
          when 0xCC then compare_with_index_y(absolute_address) # CPY absolute
          when 0xCD then compare_with_accumulator(absolute_address) # CMP absolute
          when 0xCE then decrement_memory(absolute_address) # DEC absolute
          when 0xD0 then branch_if_not_equal(relative_address) # BNE relative
          when 0xD1 then compare_with_accumulator(indirect_indexed_address_for_read) # CMP (indirect),Y
          when 0xD5 then compare_with_accumulator(zero_page_x_address) # CMP zero page,X
          when 0xD6 then decrement_memory(zero_page_x_address) # DEC zero page,X
          when 0xD8 then clear_decimal # CLD
          when 0xD9 then compare_with_accumulator(absolute_y_address_for_read) # CMP absolute,Y
          when 0xDD then compare_with_accumulator(absolute_x_address_for_read) # CMP absolute,X
          when 0xDE then decrement_memory(absolute_x_address) # DEC absolute,X
          when 0xE0 then compare_with_index_x(immediate_address) # CPX #immediate
          when 0xE1 then subtract_with_carry(indexed_indirect_address) # SBC (indirect,X)
          when 0xE4 then compare_with_index_x(zero_page_address) # CPX zero page
          when 0xE5 then subtract_with_carry(zero_page_address) # SBC zero page
          when 0xE6 then increment_memory(zero_page_address) # INC zero page
          when 0xE8 then increment_index_x # INX
          when 0xE9 then subtract_with_carry(immediate_address) # SBC #immediate
          when 0xEA then no_operation # NOP
          when 0xEC then compare_with_index_x(absolute_address) # CPX absolute
          when 0xED then subtract_with_carry(absolute_address) # SBC absolute
          when 0xEE then increment_memory(absolute_address) # INC absolute
          when 0xF0 then branch_if_equal(relative_address) # BEQ relative
          when 0xF1 then subtract_with_carry(indirect_indexed_address_for_read) # SBC (indirect),Y
          when 0xF5 then subtract_with_carry(zero_page_x_address) # SBC zero page,X
          when 0xF6 then increment_memory(zero_page_x_address) # INC zero page,X
          when 0xF8 then set_decimal # SED
          when 0xF9 then subtract_with_carry(absolute_y_address_for_read) # SBC absolute,Y
          when 0xFD then subtract_with_carry(absolute_x_address_for_read) # SBC absolute,X
          when 0xFE then increment_memory(absolute_x_address) # INC absolute,X
          else
            address = (@program_counter - 1) & Bits::WORD_MASK # glossary: wrap-to-word
            raise UnknownOpcode, format('unknown opcode $%<opcode>02X at $%<address>04X', opcode:, address:)
          end
        end
      end
    end
  end
end
