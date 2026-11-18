# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

# Cpu::Dispatch#execute is a `case` on the opcode's high nibble whose `when`s each hold a `case opcode` of that row;
# row F is the outer `else`, and each row's column 2 is its `case`'s `else` (decision 9 of docs/architecture.md).
RSpec.describe CpuBenchmark::DispatchSource do
  describe '.instructions' do
    context 'when no receiver is given' do
      context 'and the opcode has its own when' do
        context 'and its row has its own when' do
          it "is that when's instruction" do
            expect(described_class.instructions[0xA9]).to eq('load_accumulator(immediate_address)')
          end
        end

        context 'and its row is the outer else' do
          it "is that when's instruction" do
            expect(described_class.instructions[0xF0]).to eq('branch_if_equal(relative_address)')
          end
        end
      end

      context "and the opcode is its row's else" do
        context 'and it is one of the JAMs' do
          it "is the else's instruction" do
            expect(described_class.instructions[0x02]).to eq('jam')
          end
        end

        context 'and it is an instruction of its own' do
          it "is the else's instruction" do
            expect(described_class.instructions[0xA2]).to eq('load_index_x(immediate_address)')
          end
        end
      end
    end

    context 'when a receiver is given' do
      it 'sends every call of the instruction to it' do
        expect(described_class.instructions(receiver: 'cpu')[0xA9])
          .to eq('cpu.load_accumulator(cpu.immediate_address)')
      end
    end
  end
end
