# frozen_string_literal: true

require_relative '../../bench/frame_benchmark'

# The NTSC PPU makes 60.0988 frames per second (https://www.nesdev.org/wiki/Cycle_reference_chart).
RSpec.describe FrameBenchmark::Summary do
  describe '#frames_per_second' do
    subject(:summary) { described_class.new(samples) }

    let(:samples) do
      [
        FrameBenchmark::Sample.new(frames: 90, seconds: 1.0),
        FrameBenchmark::Sample.new(frames: 20, seconds: 1.0),
        FrameBenchmark::Sample.new(frames: 40, seconds: 1.0)
      ]
    end

    it "is the median of the samples' rates" do
      expect(summary.frames_per_second).to eq(40.0)
    end
  end

  describe '#milliseconds_per_frame' do
    subject(:summary) { described_class.new([FrameBenchmark::Sample.new(frames: 40, seconds: 1.0)]) }

    it 'is a thousand over that median' do
      expect(summary.milliseconds_per_frame).to eq(25.0)
    end
  end

  describe '#percent_of_real_time' do
    subject(:summary) { described_class.new([FrameBenchmark::Sample.new(frames: 601, seconds: 5.0)]) }

    it 'is that median relative to the NTSC 60.0988 frames per second' do
      expect(summary.percent_of_real_time).to be_within(1e-9).of(120.2 / 60.0988 * 100)
    end
  end

  describe '#spread' do
    subject(:summary) { described_class.new(samples) }

    let(:samples) do
      [
        FrameBenchmark::Sample.new(frames: 8, seconds: 1.0),
        FrameBenchmark::Sample.new(frames: 10, seconds: 1.0),
        FrameBenchmark::Sample.new(frames: 21, seconds: 2.0)
      ]
    end

    it 'is the farthest rate from the median, as a percentage of it' do
      expect(summary.spread).to be_within(1e-9).of(20.0)
    end
  end
end
