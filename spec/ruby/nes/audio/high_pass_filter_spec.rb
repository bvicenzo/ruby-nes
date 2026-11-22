# frozen_string_literal: true

# The NES follows its DACs with "A first-order high-pass filter at 90 Hz" (https://www.nesdev.org/wiki/APU_Mixer),
# which removes the mixer's DC offset. Modelled in the discrete RC form, from rest: RC = 1 / (2π × cut-off),
# dt = 1 / sample rate, alpha = RC / (RC + dt), output = alpha × (previous output + input − previous input).
RSpec.describe Ruby::Nes::Audio::HighPassFilter do
  describe '#filter' do
    subject(:filter) { described_class.new(cutoff:, sample_rate:) }

    let(:cutoff) { 90 }
    let(:sample_rate) { 48_000 }

    context 'when the input is silence from rest' do
      it 'outputs exactly 0' do
        expect(Array.new(100) { filter.filter(0.0) }).to all(eq(0.0))
      end
    end

    context 'when the input is a constant level' do
      let(:level) { 0.3 }
      let(:time_constant) { 1 / (2 * Math::PI * cutoff) }
      let(:sample_period) { 1.0 / sample_rate }

      it 'passes nearly the whole step on the first sample' do
        expect(filter.filter(level)).to be_within(1e-12).of(level * time_constant / (time_constant + sample_period))
      end

      it 'decays toward 0 without changing sign', :aggregate_failures do
        output = Array.new(sample_rate / 10) { filter.filter(level) }

        expect(output).to all(be_positive)
        expect(output.each_cons(2)).to all(satisfy { |earlier, later| later < earlier })
        expect(output.last).to be < 1e-6
      end
    end

    context 'when the input is a sine at the cut-off' do
      let(:input) { sine_wave(frequency: cutoff, sample_rate:, count: sample_rate / 2) }

      it 'comes out at 1/√2 of its amplitude' do
        output = input.map { filter.filter(it) }

        expect(steady_amplitude(output, frequency: cutoff, sample_rate:)).to be_within(0.01).of(Math.sqrt(0.5))
      end
    end

    context 'when the input is a sine far above the cut-off' do
      let(:frequency) { 6000 }
      let(:input) { sine_wave(frequency:, sample_rate:, count: sample_rate / 2) }

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
