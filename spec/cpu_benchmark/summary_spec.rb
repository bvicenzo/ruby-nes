# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

# The NTSC CPU runs at 1.789773 MHz (https://www.nesdev.org/wiki/Cycle_reference_chart).
RSpec.describe CpuBenchmark::Summary do
  describe '#megahertz' do
    context 'when there is one sample' do
      subject(:summary) { described_class.new([CpuBenchmark::Sample.new(cycles: 3_000_000, seconds: 1.0)]) }

      it "is that sample's" do
        expect(summary.megahertz).to be_within(1e-9).of(3.0)
      end
    end

    context 'when there is an odd number of samples' do
      subject(:summary) { described_class.new(samples) }

      let(:samples) do
        [
          CpuBenchmark::Sample.new(cycles: 9_000_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 2_000_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 4_000_000, seconds: 1.0)
        ]
      end

      it 'is the middle one in order' do
        expect(summary.megahertz).to be_within(1e-9).of(4.0)
      end
    end

    context 'when there is an even number of samples' do
      subject(:summary) { described_class.new(samples) }

      let(:samples) do
        [
          CpuBenchmark::Sample.new(cycles: 9_000_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 2_000_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 5_000_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 4_000_000, seconds: 1.0)
        ]
      end

      it 'is the mean of the two middle ones' do
        expect(summary.megahertz).to be_within(1e-9).of(4.5)
      end
    end
  end

  describe '#percent_of_real_time' do
    subject(:summary) { described_class.new([CpuBenchmark::Sample.new(cycles: 3_579_546, seconds: 1.0)]) }

    it "is the median relative to the NTSC CPU's 1.789773 MHz" do
      expect(summary.percent_of_real_time).to be_within(1e-9).of(200.0)
    end
  end

  describe '#spread' do
    context 'when the samples agree' do
      subject(:summary) { described_class.new(samples) }

      let(:samples) do
        [
          CpuBenchmark::Sample.new(cycles: 4_000_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 8_000_000, seconds: 2.0)
        ]
      end

      it 'is zero' do
        expect(summary.spread).to be_within(1e-9).of(0.0)
      end
    end

    context 'when the farthest sample is below the median' do
      subject(:summary) { described_class.new(samples) }

      let(:samples) do
        [
          CpuBenchmark::Sample.new(cycles: 8_000_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 10_000_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 10_500_000, seconds: 1.0)
        ]
      end

      it 'is its distance, as a percentage of the median' do
        expect(summary.spread).to be_within(1e-9).of(20.0)
      end
    end

    context 'when the farthest sample is above the median' do
      subject(:summary) { described_class.new(samples) }

      let(:samples) do
        [
          CpuBenchmark::Sample.new(cycles: 9_500_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 10_000_000, seconds: 1.0),
          CpuBenchmark::Sample.new(cycles: 12_000_000, seconds: 1.0)
        ]
      end

      it 'is its distance, as a percentage of the median' do
        expect(summary.spread).to be_within(1e-9).of(20.0)
      end
    end
  end
end
