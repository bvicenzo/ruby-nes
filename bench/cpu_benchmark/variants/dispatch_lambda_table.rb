# frozen_string_literal: true

# Variant for decisions 9 and 18 of docs/architecture.md: the opcode dispatch as a table of 256 lambdas indexed by
# opcode instead of one `case`. The lambdas are built once from Cpu::Dispatch's own source (plan 10, decision 5), so
# the map is the same; each takes the CPU and calls its instruction on it, one `Proc#call` per instruction.
module Ruby
  module Nes
    class Cpu
      module Dispatch
        # Each entry evaluates `->(cpu) { cpu.load_accumulator(cpu.immediate_address) }` (for $A9): code built from
        # the dispatch's own source, never from input.
        # rubocop:disable-next Security/Eval, Style/DocumentDynamicEvalDefinition
        instruction_lambdas = CpuBenchmark::DispatchSource.instructions(receiver: 'cpu').map do |instruction|
          eval("->(cpu) { #{instruction} }", binding, __FILE__, __LINE__)
        end
        INSTRUCTION_TABLE = instruction_lambdas.freeze

        private

        def execute(opcode)
          INSTRUCTION_TABLE[opcode].call(self)
        end
      end
    end
  end
end
