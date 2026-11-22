# frozen_string_literal: true

require_relative '../../bench/frame_benchmark'

require 'date'

RSpec.describe FrameBenchmark::Report do
  describe '#to_markdown' do
    context 'when the frame digests differ' do
      subject(:report) do
        described_class.new(
          title: 'Frames',
          date: Date.new(2026, 11, 22),
          ruby: 'ruby 4.0.9',
          machine: 'i5',
          measurements: [yjit, zjit]
        )
      end

      let(:yjit) do
        {
          configuration: 'yjit',
          frames_per_second: 14.0,
          milliseconds_per_frame: 71.4,
          percent_of_real_time: 23.3,
          spread: 1.0,
          frame_digest: 'a' * 64,
          audio_digest: 'c' * 64
        }
      end
      let(:zjit) do
        {
          configuration: 'zjit',
          frames_per_second: 14.0,
          milliseconds_per_frame: 71.4,
          percent_of_real_time: 23.3,
          spread: 1.0,
          frame_digest: 'b' * 64,
          audio_digest: 'c' * 64
        }
      end

      it 'says the digests differ, after the table' do
        expect(report.to_markdown).to end_with("|\n\nThe digests differ between configurations.\n")
      end
    end

    context 'when the audio digests differ' do
      subject(:report) do
        described_class.new(
          title: 'Frames',
          date: Date.new(2026, 11, 22),
          ruby: 'ruby 4.0.9',
          machine: 'i5',
          measurements: [yjit, zjit]
        )
      end

      let(:yjit) do
        {
          configuration: 'yjit',
          frames_per_second: 14.0,
          milliseconds_per_frame: 71.4,
          percent_of_real_time: 23.3,
          spread: 1.0,
          frame_digest: 'a' * 64,
          audio_digest: 'c' * 64
        }
      end
      let(:zjit) do
        {
          configuration: 'zjit',
          frames_per_second: 14.0,
          milliseconds_per_frame: 71.4,
          percent_of_real_time: 23.3,
          spread: 1.0,
          frame_digest: 'a' * 64,
          audio_digest: 'd' * 64
        }
      end

      it 'says the digests differ, after the table' do
        expect(report.to_markdown).to end_with("|\n\nThe digests differ between configurations.\n")
      end
    end

    context 'when every configuration has the same digests' do
      subject(:report) do
        described_class.new(
          title: 'Frame baseline',
          date: Date.new(2026, 11, 22),
          ruby: 'ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]',
          machine: 'Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz',
          measurements: [interpreter, yjit]
        )
      end

      let(:interpreter) do
        {
          configuration: 'interpreter',
          frames_per_second: 3.94,
          milliseconds_per_frame: 253.81,
          percent_of_real_time: 6.56,
          spread: 2.34,
          frame_digest: "0123456789ab#{'f' * 52}",
          audio_digest: "ba9876543210#{'e' * 52}"
        }
      end
      let(:yjit) do
        {
          configuration: 'yjit',
          frames_per_second: 14.26,
          milliseconds_per_frame: 70.13,
          percent_of_real_time: 23.73,
          spread: 0.96,
          frame_digest: "0123456789ab#{'f' * 52}",
          audio_digest: "ba9876543210#{'e' * 52}"
        }
      end

      it 'opens with the date, the title, the Ruby and the machine' do
        expect(report.to_markdown).to start_with(<<~MARKDOWN)
          ### 2026-11-22 — Frame baseline

          ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

        MARKDOWN
      end

      it 'has one row per measurement, in the given order, digests shortened to 12 characters' do
        expect(report.to_markdown).to end_with(<<~MARKDOWN)
          | Configuration | Frames per second | ms per frame | % of real time | Spread | Frame digest | Audio digest |
          |---|---|---|---|---|---|---|
          | interpreter | 3.9 | 253.8 | 7% | 2.3% | 0123456789ab | ba9876543210 |
          | yjit | 14.3 | 70.1 | 24% | 1.0% | 0123456789ab | ba9876543210 |
        MARKDOWN
      end

      it 'says nothing about the digests' do
        expect(report.to_markdown).not_to include('digests differ')
      end
    end
  end
end
