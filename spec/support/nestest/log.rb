# frozen_string_literal: true

module Nestest
  # The reference trace nestest ships with (Nintendulator's format), reduced to Ruby::Nes::Debug::Tracer's layout so
  # the two compare line by line (plan 08, decision 5):
  #
  #   C000  4C F5 C5  JMP $C5F5                       A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7
  #   C000  4C F5 C5  JMP  A:00 X:00 Y:00 P:24 SP:FD PPU:  0, 21 CYC:7
  #
  # The operand text is dropped (decision 1); the PPU column is kept since the tracer prints it (plan 12). The column
  # before the mnemonic is kept: `*` marks an unofficial opcode ("C6BD  04 A9    *NOP"), as the tracer marks it (plan
  # 09).
  module Log
    # Address, bytes, marker column and the three-letter mnemonic: "C000  4C F5 C5  JMP".
    INSTRUCTION_WIDTH = 19
    REGISTERS = /A:\h\h X:\h\h Y:\h\h P:\h\h SP:\h\h/
    PPU_POSITION = /PPU:[ \d]{3},[ \d]{3}/
    CYCLES = /CYC:\d+/

    def self.lines(text)
      text.each_line(chomp: true).map { |line| reduce(line) }
    end

    def self.reduce(line)
      "#{line[0, INSTRUCTION_WIDTH]}  #{line[REGISTERS]} #{line[PPU_POSITION]} #{line[CYCLES]}"
    end
    private_class_method :reduce
  end
end
