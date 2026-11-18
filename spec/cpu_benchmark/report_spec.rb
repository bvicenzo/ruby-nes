# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

require 'date'

RSpec.describe CpuBenchmark::Report do
  describe '#to_markdown' do
    context 'when the measurement is the baseline' do
      subject(:report) do
        described_class.new(
          title: 'CPU baseline',
          date: Date.new(2026, 11, 18),
          ruby: 'ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]',
          machine: 'Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz',
          measurements: [baseline]
        )
      end

      let(:baseline) do
        { configuration: 'yjit', variant: 'baseline', megahertz: 11.5, percent_of_real_time: 642.54, spread: 1.24 }
      end

      it 'heads the section with the date, the title, Ruby and the machine, then shows no change' do
        expect(report.to_markdown).to eq(<<~MARKDOWN)
          ### 2026-11-18 — CPU baseline

          ruby 4.0.9 (2026-10-23 revision 3e93b23afc) +PRISM [x86_64-darwin24]; Intel(R) Core(TM) i5-8257U CPU @ 1.40GHz

          | Configuration | Variant | Emulated MHz | % of real time | Spread | Change from baseline |
          |---|---|---|---|---|---|
          | yjit | baseline | 11.50 | 643% | 1.2% | — |
        MARKDOWN
      end
    end

    context 'when the measurement is a variant' do
      context 'but its configuration has no baseline' do
        subject(:report) do
          described_class.new(
            title: 'CPU variants',
            date: Date.new(2026, 11, 18),
            ruby: 'ruby',
            machine: 'machine',
            measurements: [variant]
          )
        end

        let(:variant) do
          { configuration: 'zjit', variant: 'memory_string', megahertz: 2.0, percent_of_real_time: 111.75, spread: 0.5 }
        end

        it 'raises KeyError' do
          expect { report.to_markdown }.to raise_error(KeyError, /zjit/)
        end
      end

      context 'and its configuration has a baseline' do
        subject(:report) do
          described_class.new(
            title: 'CPU variants',
            date: Date.new(2026, 11, 18),
            ruby: 'ruby',
            machine: 'machine',
            measurements: [interpreter_baseline, zjit_baseline, zjit_variant]
          )
        end

        let(:interpreter_baseline) do
          { configuration: 'interpreter', variant: 'baseline', megahertz: 3.6, percent_of_real_time: 201.1, spread: 1 }
        end
        let(:zjit_baseline) do
          { configuration: 'zjit', variant: 'baseline', megahertz: 2.0, percent_of_real_time: 111.75, spread: 0.5 }
        end
        let(:zjit_variant) do
          {
            configuration: 'zjit',
            variant: 'dispatch_lambda_table',
            megahertz: 2.5,
            percent_of_real_time: 139.7,
            spread: 2.0
          }
        end

        it 'shows its change from that baseline' do
          expect(report.to_markdown.lines.last)
            .to eq("| zjit | dispatch_lambda_table | 2.50 | 140% | 2.0% | +25.0% |\n")
        end
      end
    end
  end
end
