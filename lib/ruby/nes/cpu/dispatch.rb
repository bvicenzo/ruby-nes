# frozen_string_literal: true

module Ruby
  module Nes
    class Cpu
      # The opcode dispatch, included in Cpu: one `when` per opcode, official
      # (https://www.nesdev.org/wiki/Instruction_reference) or unofficial (marked `*`, as nestest.log marks them;
      # https://www.nesdev.org/wiki/CPU_unofficial_opcodes), naming the instruction and the addressing mode resolver
      # that feeds it. Indexed reads use the `_for_read` resolvers, which charge the page-cross cycle; stores and
      # read-modify-write instructions use the plain ones (plan 05, decision 2). The map is laid out as the wiki's opcode
      # matrix: one row per high nibble, one column per low nibble. Each row's column 2 is its `else` (a JAM in 12 rows,
      # the opcode $x2 in rows 8, A, C and E), and row F is the outer `else`: Ruby's branch coverage counts a `case`'s
      # implicit `else`, which a `when` for every value would leave unreachable (plan 09, decision 3; plan 10).
      # The opcode map is one method by design (decision 9 of docs/architecture.md), so the module is as long as it is.
      # rubocop:disable-next Metrics/ModuleLength
      module Dispatch
        private

        # A conscious exception to the Metrics cops (plan 06, decision 1; docs/architecture.md, Decisions log): Ruby
        # compiles a `case` whose `when`s are integer literals into `opt_case_dispatch`, with no Proc#call or `send` per
        # instruction, a shape Spinel can type, and the whole opcode map stays readable in one place. Two levels, row
        # then column, because plan 10 measured them faster than one `case` of 256 `when`s: +21% under YJIT, and +261%
        # under ZJIT, which compiles a `case` as a chain of `Integer#===` (docs/benchmarks.md). Some opcodes repeat
        # another's body (the unofficial NOPs, the two ANCs, SBC $EB); they keep one `when` each, in opcode order, so
        # the map stays a table to read by byte.
        # rubocop:disable-next Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/AbcSize, Metrics/PerceivedComplexity
        def execute(opcode)
          case opcode >> Bits::NIBBLE_WIDTH # glossary: high-nibble
          when 0x0
            case opcode
            when 0x00 then force_interrupt # BRK
            when 0x01 then or_with_accumulator(indexed_indirect_address) # ORA (indirect,X)
            when 0x03 then shift_left_then_or(indexed_indirect_address) # *SLO (indirect,X)
            when 0x04 then read_and_ignore(zero_page_address) # *NOP zero page
            when 0x05 then or_with_accumulator(zero_page_address) # ORA zero page
            when 0x06 then shift_left_memory(zero_page_address) # ASL zero page
            when 0x07 then shift_left_then_or(zero_page_address) # *SLO zero page
            when 0x08 then push_status # PHP
            when 0x09 then or_with_accumulator(immediate_address) # ORA #immediate
            when 0x0A then shift_left_accumulator # ASL accumulator
            when 0x0B then and_then_copy_sign_to_carry(immediate_address) # *ANC #immediate
            when 0x0C then read_and_ignore(absolute_address) # *NOP absolute
            when 0x0D then or_with_accumulator(absolute_address) # ORA absolute
            when 0x0E then shift_left_memory(absolute_address) # ASL absolute
            when 0x0F then shift_left_then_or(absolute_address) # *SLO absolute
            else # $02 *JAM
              jam
            end
          when 0x1
            case opcode
            when 0x10 then branch_if_plus(relative_address) # BPL relative
            when 0x11 then or_with_accumulator(indirect_indexed_address_for_read) # ORA (indirect),Y
            when 0x13 then shift_left_then_or(indirect_indexed_address) # *SLO (indirect),Y
            when 0x14 then read_and_ignore(zero_page_x_address) # *NOP zero page,X
            when 0x15 then or_with_accumulator(zero_page_x_address) # ORA zero page,X
            when 0x16 then shift_left_memory(zero_page_x_address) # ASL zero page,X
            when 0x17 then shift_left_then_or(zero_page_x_address) # *SLO zero page,X
            when 0x18 then clear_carry # CLC
            when 0x19 then or_with_accumulator(absolute_y_address_for_read) # ORA absolute,Y
            when 0x1A then no_operation # *NOP
            when 0x1B then shift_left_then_or(absolute_y_address) # *SLO absolute,Y
            when 0x1C then read_and_ignore(absolute_x_address_for_read) # *NOP absolute,X
            when 0x1D then or_with_accumulator(absolute_x_address_for_read) # ORA absolute,X
            when 0x1E then shift_left_memory(absolute_x_address) # ASL absolute,X
            when 0x1F then shift_left_then_or(absolute_x_address) # *SLO absolute,X
            else # $12 *JAM
              jam
            end
          when 0x2
            case opcode
            when 0x20 then jump_to_subroutine(absolute_address) # JSR absolute
            when 0x21 then and_with_accumulator(indexed_indirect_address) # AND (indirect,X)
            when 0x23 then rotate_left_then_and(indexed_indirect_address) # *RLA (indirect,X)
            when 0x24 then test_bits(zero_page_address) # BIT zero page
            when 0x25 then and_with_accumulator(zero_page_address) # AND zero page
            when 0x26 then rotate_left_memory(zero_page_address) # ROL zero page
            when 0x27 then rotate_left_then_and(zero_page_address) # *RLA zero page
            when 0x28 then pull_status # PLP
            when 0x29 then and_with_accumulator(immediate_address) # AND #immediate
            when 0x2A then rotate_left_accumulator # ROL accumulator
            when 0x2B then and_then_copy_sign_to_carry(immediate_address) # *ANC #immediate
            when 0x2C then test_bits(absolute_address) # BIT absolute
            when 0x2D then and_with_accumulator(absolute_address) # AND absolute
            when 0x2E then rotate_left_memory(absolute_address) # ROL absolute
            when 0x2F then rotate_left_then_and(absolute_address) # *RLA absolute
            else # $22 *JAM
              jam
            end
          when 0x3
            case opcode
            when 0x30 then branch_if_minus(relative_address) # BMI relative
            when 0x31 then and_with_accumulator(indirect_indexed_address_for_read) # AND (indirect),Y
            when 0x33 then rotate_left_then_and(indirect_indexed_address) # *RLA (indirect),Y
            when 0x34 then read_and_ignore(zero_page_x_address) # *NOP zero page,X
            when 0x35 then and_with_accumulator(zero_page_x_address) # AND zero page,X
            when 0x36 then rotate_left_memory(zero_page_x_address) # ROL zero page,X
            when 0x37 then rotate_left_then_and(zero_page_x_address) # *RLA zero page,X
            when 0x38 then set_carry # SEC
            when 0x39 then and_with_accumulator(absolute_y_address_for_read) # AND absolute,Y
            when 0x3A then no_operation # *NOP
            when 0x3B then rotate_left_then_and(absolute_y_address) # *RLA absolute,Y
            when 0x3C then read_and_ignore(absolute_x_address_for_read) # *NOP absolute,X
            when 0x3D then and_with_accumulator(absolute_x_address_for_read) # AND absolute,X
            when 0x3E then rotate_left_memory(absolute_x_address) # ROL absolute,X
            when 0x3F then rotate_left_then_and(absolute_x_address) # *RLA absolute,X
            else # $32 *JAM
              jam
            end
          when 0x4
            case opcode
            when 0x40 then return_from_interrupt # RTI
            when 0x41 then exclusive_or_with_accumulator(indexed_indirect_address) # EOR (indirect,X)
            when 0x43 then shift_right_then_exclusive_or(indexed_indirect_address) # *SRE (indirect,X)
            when 0x44 then read_and_ignore(zero_page_address) # *NOP zero page
            when 0x45 then exclusive_or_with_accumulator(zero_page_address) # EOR zero page
            when 0x46 then shift_right_memory(zero_page_address) # LSR zero page
            when 0x47 then shift_right_then_exclusive_or(zero_page_address) # *SRE zero page
            when 0x48 then push_accumulator # PHA
            when 0x49 then exclusive_or_with_accumulator(immediate_address) # EOR #immediate
            when 0x4A then shift_right_accumulator # LSR accumulator
            when 0x4B then and_then_shift_right(immediate_address) # *ALR #immediate
            when 0x4C then jump(absolute_address) # JMP absolute
            when 0x4D then exclusive_or_with_accumulator(absolute_address) # EOR absolute
            when 0x4E then shift_right_memory(absolute_address) # LSR absolute
            when 0x4F then shift_right_then_exclusive_or(absolute_address) # *SRE absolute
            else # $42 *JAM
              jam
            end
          when 0x5
            case opcode
            when 0x50 then branch_if_overflow_clear(relative_address) # BVC relative
            when 0x51 then exclusive_or_with_accumulator(indirect_indexed_address_for_read) # EOR (indirect),Y
            when 0x53 then shift_right_then_exclusive_or(indirect_indexed_address) # *SRE (indirect),Y
            when 0x54 then read_and_ignore(zero_page_x_address) # *NOP zero page,X
            when 0x55 then exclusive_or_with_accumulator(zero_page_x_address) # EOR zero page,X
            when 0x56 then shift_right_memory(zero_page_x_address) # LSR zero page,X
            when 0x57 then shift_right_then_exclusive_or(zero_page_x_address) # *SRE zero page,X
            when 0x58 then clear_interrupt_disable # CLI
            when 0x59 then exclusive_or_with_accumulator(absolute_y_address_for_read) # EOR absolute,Y
            when 0x5A then no_operation # *NOP
            when 0x5B then shift_right_then_exclusive_or(absolute_y_address) # *SRE absolute,Y
            when 0x5C then read_and_ignore(absolute_x_address_for_read) # *NOP absolute,X
            when 0x5D then exclusive_or_with_accumulator(absolute_x_address_for_read) # EOR absolute,X
            when 0x5E then shift_right_memory(absolute_x_address) # LSR absolute,X
            when 0x5F then shift_right_then_exclusive_or(absolute_x_address) # *SRE absolute,X
            else # $52 *JAM
              jam
            end
          when 0x6
            case opcode
            when 0x60 then return_from_subroutine # RTS
            when 0x61 then add_with_carry(indexed_indirect_address) # ADC (indirect,X)
            when 0x63 then rotate_right_then_add(indexed_indirect_address) # *RRA (indirect,X)
            when 0x64 then read_and_ignore(zero_page_address) # *NOP zero page
            when 0x65 then add_with_carry(zero_page_address) # ADC zero page
            when 0x66 then rotate_right_memory(zero_page_address) # ROR zero page
            when 0x67 then rotate_right_then_add(zero_page_address) # *RRA zero page
            when 0x68 then pull_accumulator # PLA
            when 0x69 then add_with_carry(immediate_address) # ADC #immediate
            when 0x6A then rotate_right_accumulator # ROR accumulator
            when 0x6B then and_then_rotate_right(immediate_address) # *ARR #immediate
            when 0x6C then jump(indirect_address) # JMP indirect
            when 0x6D then add_with_carry(absolute_address) # ADC absolute
            when 0x6E then rotate_right_memory(absolute_address) # ROR absolute
            when 0x6F then rotate_right_then_add(absolute_address) # *RRA absolute
            else # $62 *JAM
              jam
            end
          when 0x7
            case opcode
            when 0x70 then branch_if_overflow_set(relative_address) # BVS relative
            when 0x71 then add_with_carry(indirect_indexed_address_for_read) # ADC (indirect),Y
            when 0x73 then rotate_right_then_add(indirect_indexed_address) # *RRA (indirect),Y
            when 0x74 then read_and_ignore(zero_page_x_address) # *NOP zero page,X
            when 0x75 then add_with_carry(zero_page_x_address) # ADC zero page,X
            when 0x76 then rotate_right_memory(zero_page_x_address) # ROR zero page,X
            when 0x77 then rotate_right_then_add(zero_page_x_address) # *RRA zero page,X
            when 0x78 then set_interrupt_disable # SEI
            when 0x79 then add_with_carry(absolute_y_address_for_read) # ADC absolute,Y
            when 0x7A then no_operation # *NOP
            when 0x7B then rotate_right_then_add(absolute_y_address) # *RRA absolute,Y
            when 0x7C then read_and_ignore(absolute_x_address_for_read) # *NOP absolute,X
            when 0x7D then add_with_carry(absolute_x_address_for_read) # ADC absolute,X
            when 0x7E then rotate_right_memory(absolute_x_address) # ROR absolute,X
            when 0x7F then rotate_right_then_add(absolute_x_address) # *RRA absolute,X
            else # $72 *JAM
              jam
            end
          when 0x8
            # rubocop:disable-next Lint/DuplicateBranch
            case opcode
            when 0x80 then read_and_ignore(immediate_address) # *NOP #immediate
            when 0x81 then store_accumulator(indexed_indirect_address) # STA (indirect,X)
            when 0x83 then store_accumulator_and_index_x(indexed_indirect_address) # *SAX (indirect,X)
            when 0x84 then store_index_y(zero_page_address) # STY zero page
            when 0x85 then store_accumulator(zero_page_address) # STA zero page
            when 0x86 then store_index_x(zero_page_address) # STX zero page
            when 0x87 then store_accumulator_and_index_x(zero_page_address) # *SAX zero page
            when 0x88 then decrement_index_y # DEY
            when 0x89 then read_and_ignore(immediate_address) # *NOP #immediate
            when 0x8A then transfer_index_x_to_accumulator # TXA
            when 0x8B then and_index_x_and_operand(immediate_address) # *XAA #immediate
            when 0x8C then store_index_y(absolute_address) # STY absolute
            when 0x8D then store_accumulator(absolute_address) # STA absolute
            when 0x8E then store_index_x(absolute_address) # STX absolute
            when 0x8F then store_accumulator_and_index_x(absolute_address) # *SAX absolute
            else # $82 *NOP #immediate
              read_and_ignore(immediate_address)
            end
          when 0x9
            case opcode
            when 0x90 then branch_if_carry_clear(relative_address) # BCC relative
            when 0x91 then store_accumulator(indirect_indexed_address) # STA (indirect),Y
            when 0x93 then store_accumulator_and_index_x_and_high_byte(indirect_indexed_address) # *AHX (indirect),Y
            when 0x94 then store_index_y(zero_page_x_address) # STY zero page,X
            when 0x95 then store_accumulator(zero_page_x_address) # STA zero page,X
            when 0x96 then store_index_x(zero_page_y_address) # STX zero page,Y
            when 0x97 then store_accumulator_and_index_x(zero_page_y_address) # *SAX zero page,Y
            when 0x98 then transfer_index_y_to_accumulator # TYA
            when 0x99 then store_accumulator(absolute_y_address) # STA absolute,Y
            when 0x9A then transfer_index_x_to_stack_pointer # TXS
            when 0x9B then transfer_and_store_stack_pointer(absolute_y_address) # *TAS absolute,Y
            when 0x9C then store_index_y_and_high_byte(absolute_x_address) # *SHY absolute,X
            when 0x9D then store_accumulator(absolute_x_address) # STA absolute,X
            when 0x9E then store_index_x_and_high_byte(absolute_y_address) # *SHX absolute,Y
            when 0x9F then store_accumulator_and_index_x_and_high_byte(absolute_y_address) # *AHX absolute,Y
            else # $92 *JAM
              jam
            end
          when 0xA
            case opcode
            when 0xA0 then load_index_y(immediate_address) # LDY #immediate
            when 0xA1 then load_accumulator(indexed_indirect_address) # LDA (indirect,X)
            when 0xA3 then load_accumulator_and_index_x(indexed_indirect_address) # *LAX (indirect,X)
            when 0xA4 then load_index_y(zero_page_address) # LDY zero page
            when 0xA5 then load_accumulator(zero_page_address) # LDA zero page
            when 0xA6 then load_index_x(zero_page_address) # LDX zero page
            when 0xA7 then load_accumulator_and_index_x(zero_page_address) # *LAX zero page
            when 0xA8 then transfer_accumulator_to_index_y # TAY
            when 0xA9 then load_accumulator(immediate_address) # LDA #immediate
            when 0xAA then transfer_accumulator_to_index_x # TAX
            when 0xAB then and_operand_into_accumulator_and_index_x(immediate_address) # *LAX #immediate
            when 0xAC then load_index_y(absolute_address) # LDY absolute
            when 0xAD then load_accumulator(absolute_address) # LDA absolute
            when 0xAE then load_index_x(absolute_address) # LDX absolute
            when 0xAF then load_accumulator_and_index_x(absolute_address) # *LAX absolute
            else # $A2 LDX #immediate
              load_index_x(immediate_address)
            end
          when 0xB
            case opcode
            when 0xB0 then branch_if_carry_set(relative_address) # BCS relative
            when 0xB1 then load_accumulator(indirect_indexed_address_for_read) # LDA (indirect),Y
            when 0xB3 then load_accumulator_and_index_x(indirect_indexed_address_for_read) # *LAX (indirect),Y
            when 0xB4 then load_index_y(zero_page_x_address) # LDY zero page,X
            when 0xB5 then load_accumulator(zero_page_x_address) # LDA zero page,X
            when 0xB6 then load_index_x(zero_page_y_address) # LDX zero page,Y
            when 0xB7 then load_accumulator_and_index_x(zero_page_y_address) # *LAX zero page,Y
            when 0xB8 then clear_overflow # CLV
            when 0xB9 then load_accumulator(absolute_y_address_for_read) # LDA absolute,Y
            when 0xBA then transfer_stack_pointer_to_index_x # TSX
            when 0xBB then load_accumulator_index_x_and_stack_pointer(absolute_y_address_for_read) # *LAS absolute,Y
            when 0xBC then load_index_y(absolute_x_address_for_read) # LDY absolute,X
            when 0xBD then load_accumulator(absolute_x_address_for_read) # LDA absolute,X
            when 0xBE then load_index_x(absolute_y_address_for_read) # LDX absolute,Y
            when 0xBF then load_accumulator_and_index_x(absolute_y_address_for_read) # *LAX absolute,Y
            else # $B2 *JAM
              jam
            end
          when 0xC
            case opcode
            when 0xC0 then compare_with_index_y(immediate_address) # CPY #immediate
            when 0xC1 then compare_with_accumulator(indexed_indirect_address) # CMP (indirect,X)
            when 0xC3 then decrement_then_compare(indexed_indirect_address) # *DCP (indirect,X)
            when 0xC4 then compare_with_index_y(zero_page_address) # CPY zero page
            when 0xC5 then compare_with_accumulator(zero_page_address) # CMP zero page
            when 0xC6 then decrement_memory(zero_page_address) # DEC zero page
            when 0xC7 then decrement_then_compare(zero_page_address) # *DCP zero page
            when 0xC8 then increment_index_y # INY
            when 0xC9 then compare_with_accumulator(immediate_address) # CMP #immediate
            when 0xCA then decrement_index_x # DEX
            when 0xCB then and_index_x_then_subtract(immediate_address) # *AXS #immediate
            when 0xCC then compare_with_index_y(absolute_address) # CPY absolute
            when 0xCD then compare_with_accumulator(absolute_address) # CMP absolute
            when 0xCE then decrement_memory(absolute_address) # DEC absolute
            when 0xCF then decrement_then_compare(absolute_address) # *DCP absolute
            else # $C2 *NOP #immediate
              read_and_ignore(immediate_address)
            end
          when 0xD
            case opcode
            when 0xD0 then branch_if_not_equal(relative_address) # BNE relative
            when 0xD1 then compare_with_accumulator(indirect_indexed_address_for_read) # CMP (indirect),Y
            when 0xD3 then decrement_then_compare(indirect_indexed_address) # *DCP (indirect),Y
            when 0xD4 then read_and_ignore(zero_page_x_address) # *NOP zero page,X
            when 0xD5 then compare_with_accumulator(zero_page_x_address) # CMP zero page,X
            when 0xD6 then decrement_memory(zero_page_x_address) # DEC zero page,X
            when 0xD7 then decrement_then_compare(zero_page_x_address) # *DCP zero page,X
            when 0xD8 then clear_decimal # CLD
            when 0xD9 then compare_with_accumulator(absolute_y_address_for_read) # CMP absolute,Y
            when 0xDA then no_operation # *NOP
            when 0xDB then decrement_then_compare(absolute_y_address) # *DCP absolute,Y
            when 0xDC then read_and_ignore(absolute_x_address_for_read) # *NOP absolute,X
            when 0xDD then compare_with_accumulator(absolute_x_address_for_read) # CMP absolute,X
            when 0xDE then decrement_memory(absolute_x_address) # DEC absolute,X
            when 0xDF then decrement_then_compare(absolute_x_address) # *DCP absolute,X
            else # $D2 *JAM
              jam
            end
          when 0xE
            # rubocop:disable-next Lint/DuplicateBranch
            case opcode
            when 0xE0 then compare_with_index_x(immediate_address) # CPX #immediate
            when 0xE1 then subtract_with_carry(indexed_indirect_address) # SBC (indirect,X)
            when 0xE3 then increment_then_subtract(indexed_indirect_address) # *ISB (indirect,X)
            when 0xE4 then compare_with_index_x(zero_page_address) # CPX zero page
            when 0xE5 then subtract_with_carry(zero_page_address) # SBC zero page
            when 0xE6 then increment_memory(zero_page_address) # INC zero page
            when 0xE7 then increment_then_subtract(zero_page_address) # *ISB zero page
            when 0xE8 then increment_index_x # INX
            when 0xE9 then subtract_with_carry(immediate_address) # SBC #immediate
            when 0xEA then no_operation # NOP
            when 0xEB then subtract_with_carry(immediate_address) # *SBC #immediate
            when 0xEC then compare_with_index_x(absolute_address) # CPX absolute
            when 0xED then subtract_with_carry(absolute_address) # SBC absolute
            when 0xEE then increment_memory(absolute_address) # INC absolute
            when 0xEF then increment_then_subtract(absolute_address) # *ISB absolute
            else # $E2 *NOP #immediate
              read_and_ignore(immediate_address)
            end
          else # $F0-$FF
            case opcode
            when 0xF0 then branch_if_equal(relative_address) # BEQ relative
            when 0xF1 then subtract_with_carry(indirect_indexed_address_for_read) # SBC (indirect),Y
            when 0xF3 then increment_then_subtract(indirect_indexed_address) # *ISB (indirect),Y
            when 0xF4 then read_and_ignore(zero_page_x_address) # *NOP zero page,X
            when 0xF5 then subtract_with_carry(zero_page_x_address) # SBC zero page,X
            when 0xF6 then increment_memory(zero_page_x_address) # INC zero page,X
            when 0xF7 then increment_then_subtract(zero_page_x_address) # *ISB zero page,X
            when 0xF8 then set_decimal # SED
            when 0xF9 then subtract_with_carry(absolute_y_address_for_read) # SBC absolute,Y
            when 0xFA then no_operation # *NOP
            when 0xFB then increment_then_subtract(absolute_y_address) # *ISB absolute,Y
            when 0xFC then read_and_ignore(absolute_x_address_for_read) # *NOP absolute,X
            when 0xFD then subtract_with_carry(absolute_x_address_for_read) # SBC absolute,X
            when 0xFE then increment_memory(absolute_x_address) # INC absolute,X
            when 0xFF then increment_then_subtract(absolute_x_address) # *ISB absolute,X
            else # $F2 *JAM
              jam
            end
          end
        end
      end
    end
  end
end
