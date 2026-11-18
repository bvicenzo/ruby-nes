# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

RSpec.describe CpuBenchmark::Sample do
  describe '#megahertz' do
    subject(:sample) { described_class.new(cycles: 5_000_000, seconds: 2.0) }

    it 'is the emulated cycles per second, in millions' do
      expect(sample.megahertz).to be_within(1e-9).of(2.5)
    end
  end
end
