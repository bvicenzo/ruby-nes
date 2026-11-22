# frozen_string_literal: true

# The NES follows its DACs with "A first-order low-pass filter at 14 kHz" (https://www.nesdev.org/wiki/APU_Mixer).
# Modelled in the discrete RC form, from rest: RC = 1 / (2π × cut-off), dt = 1 / sample rate, beta = dt / (RC + dt),
# output = previous output + beta × (input − previous output). Near the Nyquist frequency the discrete form attenuates
# more than the analogue filter (14 kHz at 48 kHz comes out at 0.55 rather than 1/√2; plan 24), so the cut-off is
# checked here at 100 Hz.
RSpec.describe Ruby::Nes::Audio::LowPassFilter do
  describe '#filter' do
    subject(:filter) { described_class.new(cutoff:, sample_rate:) }

    let(:cutoff) { 100 }
    let(:sample_rate) { 48_000 }

    context 'when the input is silence from rest' do
      it 'outputs exactly 0' do
        expect(Array.new(100) { filter.filter(0.0) }).to all(eq(0.0))
      end
    end

    context 'when the input is a constant level' do
      let(:level) { 0.3 }

      it 'rises toward the level and settles at it without overshooting', :aggregate_failures do
        output = Array.new(sample_rate / 10) { filter.filter(level) }

        expect(output.each_cons(2)).to all(satisfy { |earlier, later| later >= earlier })
        expect(output).to all(be <= level)
        expect(output.first).to be < level / 2
        expect(output.last).to be_within(1e-9).of(level)
      end
    end

    context 'when the input is a sine at the cut-off' do
      let(:input) { sine_wave(frequency: cutoff, sample_rate:, count: sample_rate / 2) }

      it 'comes out at 1/√2 of its amplitude' do
        output = input.map { filter.filter(it) }

        expect(steady_amplitude(output, frequency: cutoff, sample_rate:)).to be_within(0.01).of(Math.sqrt(0.5))
      end
    end

    context 'when the input is a sine far below the cut-off' do
      let(:frequency) { 5 }
      let(:input) { sine_wave(frequency:, sample_rate:, count: sample_rate) }

      it 'passes almost unchanged' do
        output = input.map { filter.filter(it) }

        expect(steady_amplitude(output, frequency:, sample_rate:)).to be_within(0.01).of(1.0)
      end
    end

    context 'when another filter has filtered other samples' do
      let(:other_filter) { described_class.new(cutoff:, sample_rate:) }

      before { 10.times { other_filter.filter(0.3) } }

      it 'keeps its own state' do
        expect(filter.filter(0.0)).to eq(0.0)
      end
    end
  end
end
