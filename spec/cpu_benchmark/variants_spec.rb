# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

RSpec.describe CpuBenchmark::Variants do
  describe '.path' do
    context 'when the name is not a variant' do
      it 'raises UnknownVariant listing the variants' do
        expect { described_class.path('memory_hash') }
          .to raise_error(CpuBenchmark::UnknownVariant, /memory_hash.*dispatch_lambda_table, .*interrupt_poll_inline/)
      end
    end

    context 'when the name is a variant' do
      it 'is its file under bench/cpu_benchmark/variants' do
        expect(described_class.path('memory_string'))
          .to eq(File.expand_path('../../bench/cpu_benchmark/variants/memory_string.rb', __dir__))
      end
    end
  end
end
