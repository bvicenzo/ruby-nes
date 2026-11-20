# frozen_string_literal: true

require_relative '../../bench/frontend_benchmark'

# The tone of the audio smoke test (plan 17): a square wave, high for the first half of each period and low for the
# second, computed from each sample's index so that it neither drifts nor clicks between calls.
RSpec.describe FrontendBenchmark::SquareWave do
  describe '#samples' do
    subject(:square_wave) { described_class.new(frequency:, sample_rate:, amplitude: 100) }

    context 'when no sample is asked' do
      let(:frequency) { 1 }
      let(:sample_rate) { 8 }

      it 'returns none' do
        expect(square_wave.samples(0)).to eq([])
      end

      it 'leaves the phase where it was' do
        square_wave.samples(3)
        square_wave.samples(0)

        expect(square_wave.samples(2)).to eq([100, -100])
      end
    end

    context 'when samples are asked' do
      context 'and they stay within the first half of a period' do
        let(:frequency) { 1 }
        let(:sample_rate) { 8 }

        it 'returns them all high' do
          expect(square_wave.samples(4)).to eq([100, 100, 100, 100])
        end
      end

      context 'and they reach half a period' do
        let(:frequency) { 1 }
        let(:sample_rate) { 8 }

        it 'turns low at exactly half a period' do
          expect(square_wave.samples(8)).to eq([100, 100, 100, 100, -100, -100, -100, -100])
        end
      end

      context 'and they run past a whole period' do
        let(:frequency) { 1 }
        let(:sample_rate) { 8 }

        it 'turns high again at the next period' do
          expect(square_wave.samples(10).last(3)).to eq([-100, 100, 100])
        end
      end

      context 'and the period is not a whole number of samples' do
        let(:frequency) { 3 }
        let(:sample_rate) { 10 }

        it 'makes exactly as many periods per second as its frequency' do
          expect(square_wave.samples(10)).to eq([100, 100, -100, -100, 100, -100, -100, 100, 100, -100])
        end
      end

      context 'and samples were asked before' do
        let(:frequency) { 3 }
        let(:sample_rate) { 10 }

        it 'continues where the previous call stopped' do
          square_wave.samples(4)

          expect(square_wave.samples(6)).to eq([100, -100, -100, 100, 100, -100])
        end
      end
    end
  end
end
