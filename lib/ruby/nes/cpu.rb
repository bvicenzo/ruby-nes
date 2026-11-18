# frozen_string_literal: true

# Loaded first: Cpu includes AddressingModes. The nested files need only Bits, already loaded by ruby/nes.
require_relative 'cpu/status'
require_relative 'cpu/stack'
require_relative 'cpu/addressing_modes'

module Ruby
  module Nes
    # The 6502 core of the 2A03 (https://www.nesdev.org/wiki/CPU), without decimal mode. Registers
    # (https://www.nesdev.org/wiki/CPU_registers): A, X and Y are byte-wide, the program counter has 16 bits, S lives in
    # the Stack and P in the Status. Every register starts at zero until plan 07 defines the power-up state; specs and
    # tools may give A, X, Y and the program counter initial values as keywords.
    class Cpu
      include AddressingModes

      attr_accessor :accumulator, :index_x, :index_y, :program_counter
      attr_reader :status, :stack, :cycles

      def initialize(bus:, accumulator: 0, index_x: 0, index_y: 0, program_counter: 0)
        @bus = bus
        @accumulator = accumulator
        @index_x = index_x
        @index_y = index_y
        @program_counter = program_counter
        @status = Status.new
        @stack = Stack.new(bus:)
        @cycles = 0
      end

      # The byte at the program counter, which then moves to the next byte.
      def fetch_byte
        byte = @bus.read(@program_counter)
        @program_counter = (@program_counter + 1) & Bits::WORD_MASK # glossary: wrap-to-word
        byte
      end

      # The little-endian word at the program counter, which then moves past it.
      def fetch_word
        low = fetch_byte
        high = fetch_byte
        (high << 8) | low # glossary: combine-bytes
      end
    end
  end
end
