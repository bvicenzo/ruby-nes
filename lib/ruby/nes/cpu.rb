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
require_relative 'cpu/instructions/read_modify_write_combos'
require_relative 'cpu/instructions/immediate_combos'
require_relative 'cpu/instructions/unstable'
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
      # Interrupt vectors, each a little-endian address (https://www.nesdev.org/wiki/CPU_interrupts): NMI at $FFFA,
      # reset at $FFFC, IRQ and BRK at $FFFE.
      NMI_VECTOR = 0xFFFA
      RESET_VECTOR = 0xFFFC
      IRQ_VECTOR = 0xFFFE

      # What a #step costs while a JAM opcode keeps the CPU halted. A convention, not hardware: no reference found gives
      # the cycles of a jammed CPU nor says whether NMI and IRQ act on it (plan 09, decision 2; docs/architecture.md,
      # Known gaps). The clock keeps running on hardware, so the console must keep advancing the PPU and APU.
      JAMMED_STEP_CYCLES = 2
      # An instruction's data access falls on its last cycle, the one before the cycle it ends on.
      ACCESS_CYCLE_OFFSET = 1

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
      include Instructions::ReadModifyWriteCombos
      include Instructions::ImmediateCombos
      include Instructions::Unstable
      include Interrupts
      include Dispatch

      attr_accessor :accumulator, :index_x, :index_y, :program_counter
      attr_reader :status, :stack, :cycles
      # Catches the PPU up before an interrupt sequence picks its vector, so an NMI edge that hijacks it is known
      # (plan 22, decision 1): the console's register sync. Without one, the sequence uses the edges already told.
      attr_writer :interrupt_sync

      # One optional keyword per register of the register file, plus the cycle count, so specs can start anywhere.
      # rubocop:disable-next Metrics/ParameterLists
      def initialize(bus:, accumulator: 0, index_x: 0, index_y: 0, program_counter: 0, stack_pointer: 0, cycles: 0)
        @bus = bus
        @accumulator = accumulator
        @index_x = index_x
        @index_y = index_y
        @program_counter = program_counter
        @status = Status.new
        @shifter = Shifter.new(status: @status)
        @stack = Stack.new(bus:, pointer: stack_pointer)
        @interrupt_lines = InterruptLines.new(status: @status)
        @interrupt_sync = nil
        @cycles = cycles
        @jammed = false
      end

      # Whether a JAM opcode halted the CPU; only #reset releases it (plan 09, decision 2).
      def jammed? = @jammed

      # The cycle the running instruction makes its data access on: its last one, before the cycle it ends on, since
      # #step charges the cycles first and every non-read-modify-write instruction accesses memory on its last cycle
      # (https://www.nesdev.org/6502_cpu.txt; plan 12, decision 1). Devices stamp register effects with it.
      def access_cycle = @cycles - ACCESS_CYCLE_OFFSET

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
      # while it ran, plus the cycles a DMA the step started halts the CPU for, which the bus reports (plan 11,
      # decision 3). A jammed CPU does neither: it touches no bus and takes JAMMED_STEP_CYCLES.
      #
      # The base cycles are charged before the instruction runs (plan 12, decision 1), so at its data access `cycles` is
      # the cycle it ends on: the register sync catches the PPU up to the access from there.
      def step
        return stay_jammed if @jammed

        cycles_before = @cycles
        vector = @interrupt_lines.acknowledge(@cycles)
        if vector
          take_interrupt(vector)
        else
          opcode = fetch_byte
          @cycles += Opcodes::TABLE[opcode].cycles
          execute(opcode)
        end
        add_stall_cycles
        @cycles - cycles_before
      end

      private

      # A DMA the step started halts the CPU for the cycles the bus reports. The CPU polled for interrupts before the
      # halt and polls nothing during it, so the next poll looks back past the stall (plan 22, decision 9).
      def add_stall_cycles
        stall_cycles = @bus.take_stall_cycles(@cycles)
        return if stall_cycles.zero?

        @interrupt_lines.poll_before_stall(stall_cycles)
        @cycles += stall_cycles
      end

      def stay_jammed
        @cycles += JAMMED_STEP_CYCLES
        JAMMED_STEP_CYCLES
      end

      # The write step of every read-modify-write instruction on memory: it "first [writes] the original value back to
      # memory" (https://www.nesdev.org/wiki/Instruction_reference), "then modified"
      # (https://www.nesdev.org/6502_cpu.txt), so a device that reacts to each write, such as the MMC1 serial port,
      # sees both. Returns the modified byte.
      def write_modified(address, original, modified)
        @bus.write(address, original)
        @bus.write(address, modified)
        modified
      end

      # The little-endian word at `address`, such as an interrupt vector; the high byte's address wraps past $FFFF.
      def read_word(address)
        low = @bus.read(address)
        high = @bus.read((address + 1) & Bits::WORD_MASK) # glossary: wrap-to-word
        (high << 8) | low # glossary: combine-bytes
      end
    end
  end
end
