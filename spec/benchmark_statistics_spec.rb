# frozen_string_literal: true

require_relative '../bench/benchmark_statistics'

RSpec.describe BenchmarkStatistics do
  describe '.median' do
    context 'when there is one value' do
      it 'is that value' do
        expect(described_class.median([3.0])).to eq(3.0)
      end
    end

    context 'when there is an odd number of values' do
      it 'is the middle one in order' do
        expect(described_class.median([9.0, 2.0, 4.0])).to eq(4.0)
      end
    end

    context 'when there is an even number of values' do
      it 'is the mean of the two middle ones' do
        expect(described_class.median([9, 2, 5, 4])).to eq(4.5)
      end
    end
  end

  describe '.spread' do
    context 'when the values agree' do
      it 'is zero' do
        expect(described_class.spread([4.0, 4.0])).to eq(0.0)
      end
    end

    context 'when the farthest value is below the median' do
      it 'is its distance, as a percentage of the median' do
        expect(described_class.spread([8, 10, 11])).to be_within(1e-9).of(20.0)
      end
    end

    context 'when the farthest value is above the median' do
      it 'is its distance, as a percentage of the median' do
        expect(described_class.spread([9, 10, 12])).to be_within(1e-9).of(20.0)
      end
    end
  end
end
