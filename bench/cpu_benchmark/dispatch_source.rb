# frozen_string_literal: true

require 'prism'

module CpuBenchmark
  # The opcode map of Cpu::Dispatch#execute read from its source with Prism, so the dispatch variants rebuild the same
  # map in another shape without copying it by hand (plan 10, decision 5). The map is a `case` per row of the opcode
  # matrix (`case opcode`), each with a `when` per opcode and an `else` for the one opcode of the row left out.
  module DispatchSource
    FILE = File.expand_path('../../lib/ruby/nes/cpu/dispatch.rb', __dir__)
    OPCODE_COUNT = 256
    OPCODES_PER_ROW = 16

    # The source of each opcode's instruction call, indexed by opcode (`'load_accumulator(immediate_address)'` at
    # $A9); an opcode without a `when` takes its row's `else` (`'jam'` at $02). With a `receiver`, every call is sent
    # to it (`'cpu.load_accumulator(cpu.immediate_address)'`), for code that runs outside the CPU.
    def self.instructions(receiver: nil)
      instructions = Array.new(OPCODE_COUNT)
      row_cases(Prism.parse_file(FILE).value).each do |row_case|
        row_case.conditions.each do |opcode_branch|
          instruction = call_source(opcode_branch.statements, receiver)
          opcode_branch.conditions.each { |opcode| instructions[opcode.value] = instruction }
        end
        fill_row(instructions, row_case, call_source(row_case.else_clause.statements, receiver))
      end
      instructions
    end

    # Every `case opcode` of the dispatch, the rows.
    def self.row_cases(node)
      own_case = node.is_a?(Prism::CaseNode) && node.predicate.is_a?(Prism::LocalVariableReadNode) ? [node] : []
      own_case + node.compact_child_nodes.flat_map { |child| row_cases(child) }
    end
    private_class_method :row_cases

    # The opcodes of the row that no `when` names take the `else`'s instruction.
    def self.fill_row(instructions, row_case, else_instruction)
      row = Ruby::Nes::Bits.high_nibble(row_case.conditions.first.conditions.first.value)
      OPCODES_PER_ROW.times do |column|
        opcode = Ruby::Nes::Bits.combine_nibbles(low: column, high: row)
        instructions[opcode] ||= else_instruction
      end
    end
    private_class_method :fill_row

    # The statement's source with `receiver.` in front of each call that has none, inserted from the last call to the
    # first so the earlier offsets stay valid.
    def self.call_source(statements, receiver)
      source = statements.slice.dup
      return source unless receiver

      start = statements.location.start_offset
      receiverless_call_offsets(statements).sort.reverse_each do |offset|
        source.insert(offset - start, "#{receiver}.")
      end
      source
    end
    private_class_method :call_source

    def self.receiverless_call_offsets(node)
      own_offset = node.is_a?(Prism::CallNode) && node.receiver.nil? ? [node.location.start_offset] : []
      own_offset + node.compact_child_nodes.flat_map { |child| receiverless_call_offsets(child) }
    end
    private_class_method :receiverless_call_offsets
  end
end
