# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

RSpec.describe CpuBenchmark::Configuration do
  describe '.current' do
    context 'when ZJIT is enabled' do
      it "is 'zjit'" do
        expect(described_class.current(yjit_enabled: false, zjit_enabled: true)).to eq('zjit')
      end
    end

    context 'when YJIT is enabled' do
      it "is 'yjit'" do
        expect(described_class.current(yjit_enabled: true, zjit_enabled: false)).to eq('yjit')
      end
    end

    context 'when no JIT is enabled' do
      it "is 'interpreter'" do
        expect(described_class.current(yjit_enabled: false, zjit_enabled: false)).to eq('interpreter')
      end
    end
  end
end
