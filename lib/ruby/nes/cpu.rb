# frozen_string_literal: true

# Loaded first: Cpu includes AddressingModes, Dispatch and the instruction groups. The nested files need only Bits,
# already loaded by ruby/nes.
require_relative 'cpu/status'
require_relative 'cpu/stack'
require_relative 'cpu/shifter'
require_relative 'cpu/opcodes'
require_relative 'cpu/addressing_modes'
require_relative 'cpu/instructions/load_store'
require_relative 'cpu/instructions/transfers'
require_relative 'cpu/instructions/stack_operations'
require_relative 'cpu/instructions/logic'
require_relative 'cpu/instructions/arithmetic'
require_relative 'cpu/instructions/comparisons'
require_relative 'cpu/instructions/increment_decrement'
require_relative 'cpu/instructions/shifts'
require_relative 'cpu/instructions/branches'
require_relative 'cpu/instructions/flags'
require_relative 'cpu/instructions/control_flow'
require_relative 'cpu/interrupt_lines'
require_relative 'cpu/interrupts'
require_relative 'cpu/dispatch'

module Ruby
  module Nes
    # The 6502 core of the 2A03 (https://www.nesdev.org/wiki/CPU), without decimal mode. Registers
    # (https://www.nesdev.org/wiki/CPU_registers): A, X and Y are byte-wide, the program counter has 16 bits, S lives in
    # the Stack and P in the Status. Every register starts at zero, the state before the power-up reset sequence
    # (https://www.nesdev.org/wiki/CPU_power_up_state): power-up is `Cpu.new` followed by #reset. Specs and tools may
    # give A, X, Y, the program counter and the stack pointer initial values as keywords.
    class Cpu
      # Raised by #step for an opcode outside the official 151 (unofficial opcodes are plan 09).
      class UnknownOpcode < Nes::Error; end

      # Interrupt vectors, each a little-endian address (https://www.nesdev.org/wiki/CPU_interrupts): NMI at $FFFA,
      # reset at $FFFC, IRQ and BRK at $FFFE.
      NMI_VECTOR = 0xFFFA
      RESET_VECTOR = 0xFFFC
      IRQ_VECTOR = 0xFFFE

      include AddressingModes
      include Instructions::LoadStore
      include Instructions::Transfers
      include Instructions::StackOperations
      include Instructions::Logic
      include Instructions::Arithmetic
      include Instructions::Comparisons
      include Instructions::IncrementDecrement
      include Instructions::Shifts
      include Instructions::Branches
      include Instructions::Flags
      include Instructions::ControlFlow
      include Interrupts
      include Dispatch

      attr_accessor :accumulator, :index_x, :index_y, :program_counter
      attr_reader :status, :stack, :cycles

      # One optional keyword per register of the register file: the list is as long as the hardware's.
      # rubocop:disable-next Metrics/ParameterLists
      def initialize(bus:, accumulator: 0, index_x: 0, index_y: 0, program_counter: 0, stack_pointer: 0)
        @bus = bus
        @accumulator = accumulator
        @index_x = index_x
        @index_y = index_y
        @program_counter = program_counter
        @status = Status.new
        @shifter = Shifter.new(status: @status)
        @stack = Stack.new(bus:, pointer: stack_pointer)
        @interrupt_lines = InterruptLines.new(status: @status)
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

      # Takes the interrupt InterruptLines names, if any, or else runs the instruction at the program counter; returns
      # the cycles it took: 7 for an interrupt, or the opcode's base cycles plus any page-cross or branch cycle charged
      # while it ran. Raises UnknownOpcode for an opcode outside the official 151.
      def step
        cycles_before = @cycles
        vector = @interrupt_lines.acknowledge
        if vector
          take_interrupt(vector)
        else
          opcode = fetch_byte
          execute(opcode)
          @cycles += Opcodes::TABLE[opcode].cycles
        end
        @cycles - cycles_before
      end

      private

      # The little-endian word at `address`, such as an interrupt vector; the high byte's address wraps past $FFFF.
      def read_word(address)
        low = @bus.read(address)
        high = @bus.read((address + 1) & Bits::WORD_MASK) # glossary: wrap-to-word
        (high << 8) | low # glossary: combine-bytes
      end
    end
  end
end
