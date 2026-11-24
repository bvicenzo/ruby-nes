# frozen_string_literal: true

require_relative '../../bench/cpu_benchmark'

RSpec.describe CpuBenchmark::Configuration do
  describe '.current' do
    context 'when the engine is not CRuby' do
      it "is the engine's name" do
        expect(described_class.current(yjit_enabled: false, zjit_enabled: false, engine: 'spinel')).to eq('spinel')
      end
    end

    context 'when the engine is CRuby' do
      context 'and ZJIT is enabled' do
        context 'and YJIT is not' do
          it "is 'zjit'" do
            expect(described_class.current(yjit_enabled: false, zjit_enabled: true, engine: 'ruby')).to eq('zjit')
          end
        end

        context 'and YJIT is reported enabled too' do
          it "is 'zjit'" do
            expect(described_class.current(yjit_enabled: true, zjit_enabled: true, engine: 'ruby')).to eq('zjit')
          end
        end
      end

      context 'and ZJIT is not enabled' do
        context 'but YJIT is' do
          it "is 'yjit'" do
            expect(described_class.current(yjit_enabled: true, zjit_enabled: false, engine: 'ruby')).to eq('yjit')
          end
        end

        context 'and YJIT is not' do
          it "is 'interpreter'" do
            configuration = described_class.current(yjit_enabled: false, zjit_enabled: false, engine: 'ruby')

            expect(configuration).to eq('interpreter')
          end
        end
      end
    end
  end
end
