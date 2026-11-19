# frozen_string_literal: true

module Ruby
  module Nes
    module Debug
      # One line per instruction, describing the CPU *before* it runs, laid out like nestest's reference log up to the
      # mnemonic and then showing the machine state only (plan 08, decision 5):
      #
      #   C000  4C F5 C5  JMP  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7
      #   C6BD  04 A9    *NOP  A:AA X:97 Y:4E P:EF SP:F9 PPU:128, 89 CYC:14579
      #
      # An unofficial opcode has `*` in the column before its mnemonic, as nestest.log marks it (plan 09). The state ends
      # with nestest's PPU column, scanline and dot (plan 12). When the next step takes an interrupt, a step of its own
      # (decision 14 of docs/architecture.md), the line names it in place of the instruction; a jammed CPU (plan 09)
      # shows the halt:
      #
      #   C000  NMI            A:00 X:00 Y:00 P:24 SP:FD PPU:241,  5 CYC:27397
      #   C001  JAMMED         A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 27 CYC:9
      #
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
        # An interrupt or the halt in place of the bytes, marker and mnemonic columns, so the state lines up.
        EVENT_LINE_FORMAT = '%<address>04X  %<event>-13s  %<state>s'
        STATE_FORMAT = 'A:%<accumulator>02X X:%<index_x>02X Y:%<index_y>02X P:%<status>02X SP:%<stack_pointer>02X ' \
                       'PPU:%<scanline>3d,%<dot>3d CYC:%<cycles>d'
        INTERRUPT_NAMES = { Cpu::NMI_VECTOR => 'NMI', Cpu::IRQ_VECTOR => 'IRQ' }.freeze
        JAMMED = 'JAMMED'

        def initialize(cpu:, bus:, ppu:)
          @cpu = cpu
          @bus = bus
          @ppu = ppu
        end

        def line
          return event_line(JAMMED) if @cpu.jammed?

          vector = @cpu.pending_interrupt
          vector ? event_line(INTERRUPT_NAMES.fetch(vector)) : instruction_line
        end

        private

        def event_line(event) = format(EVENT_LINE_FORMAT, address: @cpu.program_counter, event:, state:)

        def instruction_line
          address = @cpu.program_counter
          opcode_byte = @bus.read(address)
          opcode = Cpu::Opcodes::TABLE[opcode_byte]
          bytes = instruction_bytes(address, opcode_byte, opcode.size).ljust(BYTES_COLUMN_WIDTH)
          marker = opcode.official? ? OFFICIAL_MARKER : UNOFFICIAL_MARKER

          format(LINE_FORMAT, address:, bytes:, marker:, mnemonic: opcode.mnemonic, state:)
        end

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
            scanline: @ppu.scanline,
            dot: @ppu.dot,
            cycles: @cpu.cycles
          )
        end
      end
    end
  end
end
