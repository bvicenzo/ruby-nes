# frozen_string_literal: true

require_relative '../../bench/frame_benchmark'

RSpec.describe FrameBenchmark::Sample do
  describe '#frames_per_second' do
    subject(:sample) { described_class.new(frames: 60, seconds: 4.0) }

    it 'is the frames over the seconds' do
      expect(sample.frames_per_second).to eq(15.0)
    end
  end
end
