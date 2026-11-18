# frozen_string_literal: true

module Ruby
  module Nes
    module Debug
      # One line per instruction, describing the CPU *before* it runs, laid out like nestest's reference log up to the
      # mnemonic and then showing the machine state only (plan 08, decision 5):
      #
      #   C000  4C F5 C5  JMP  A:00 X:00 Y:00 P:24 SP:FD CYC:7
      #   C6BD  04 A9    *NOP  A:AA X:97 Y:4E P:EF SP:F9 CYC:14579
      #
      # An unofficial opcode has `*` in the column before its mnemonic, as nestest.log marks it (plan 09).
      # P is the byte an interrupt would push (bit 5 set, B clear), nestest's convention: debuggers have "no
      # convention" for those bits (https://www.nesdev.org/wiki/Status_flags). The instruction's bytes are read with
      # the bus's own `read` (decision 2): they are the bytes the CPU fetches next, so the data bus ends the same once
      # the instruction runs. Debug tooling, off the hot path.
      class Tracer
        OFFICIAL_MARKER = ' '
        UNOFFICIAL_MARKER = '*'
        # The widest instruction, three bytes as "4C F5 C5", so shorter ones line up with it.
        BYTES_COLUMN_WIDTH = 8
        LINE_FORMAT = '%<address>04X  %<bytes>s %<marker>s%<mnemonic>s  %<state>s'
        STATE_FORMAT = 'A:%<accumulator>02X X:%<index_x>02X Y:%<index_y>02X P:%<status>02X SP:%<stack_pointer>02X ' \
                       'CYC:%<cycles>d'

        def initialize(cpu:, bus:)
          @cpu = cpu
          @bus = bus
        end

        def line
          address = @cpu.program_counter
          opcode_byte = @bus.read(address)
          opcode = Cpu::Opcodes::TABLE[opcode_byte]
          bytes = instruction_bytes(address, opcode_byte, opcode.size).ljust(BYTES_COLUMN_WIDTH)
          marker = opcode.official? ? OFFICIAL_MARKER : UNOFFICIAL_MARKER

          format(LINE_FORMAT, address:, bytes:, marker:, mnemonic: opcode.mnemonic, state:)
        end

        private

        # The instruction's bytes as hexadecimal pairs: the opcode already read, then its operand, each byte read once;
        # past $FFFF the operand comes from $0000, as the CPU fetches it.
        def instruction_bytes(address, opcode_byte, size)
          operand_bytes = (1...size).map { |offset| @bus.read(Bits.wrap_to_word(address + offset)) }

          [opcode_byte, *operand_bytes].map { |byte| format('%02X', byte) }.join(' ')
        end

        def state
          format(
            STATE_FORMAT,
            accumulator: @cpu.accumulator,
            index_x: @cpu.index_x,
            index_y: @cpu.index_y,
            status: @cpu.status.byte_pushed_by_interrupt,
            stack_pointer: @cpu.stack.pointer,
            cycles: @cpu.cycles
          )
        end
      end
    end
  end
end
