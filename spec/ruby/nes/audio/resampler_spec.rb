# frozen_string_literal: true

# A box resampler (plan 24, decision 4): it takes the APU's level every CPU cycle and, at the end of each output
# period, pushes the mean of the levels of that period. The period is kept as an exact fraction of cycles, so the
# samples never drift: the CPU clock is the master clock ÷ 12, "236.25 MHz ÷ 11 by definition"
# (https://www.nesdev.org/wiki/Cycle_reference_chart), 945 000 000 / 528 Hz.
RSpec.describe Ruby::Nes::Audio::Resampler do
  describe '#add' do
    let(:output) { instance_double(Ruby::Nes::Audio::OutputStage, push: nil) }

    context 'when the period is a whole number of cycles' do
      subject(:resampler) { described_class.new(output_rate: 1, output:, input_rate: 4) }

      context 'and fewer cycles than a period were added' do
        before { [0.1, 0.2, 0.3].each { resampler.add(it) } }

        it 'pushes nothing' do
          expect(output).not_to have_received(:push)
        end
      end

      context 'and a whole period was added' do
        before { [0.1, 0.2, 0.3, 0.6].each { resampler.add(it) } }

        it "pushes the mean of the period's levels" do
          expect(output).to have_received(:push).once.with(a_value_within(1e-12).of(0.3))
        end
      end

      context 'and two periods were added' do
        before { [0.1, 0.2, 0.3, 0.6, 1.0, 1.0, 0.0, 0.0].each { resampler.add(it) } }

        it 'averages each period on its own', :aggregate_failures do
          expect(output).to have_received(:push).with(a_value_within(1e-12).of(0.3)).ordered
          expect(output).to have_received(:push).with(a_value_within(1e-12).of(0.5)).ordered
        end
      end
    end

    context 'when the period is a fraction of cycles' do
      subject(:resampler) { described_class.new(output_rate: 2, output:, input_rate: 5) }

      before { [0.3, 0.6, 0.9, 0.2, 0.4].each { resampler.add(it) } }

      it 'alternates periods of three and two cycles', :aggregate_failures do
        expect(output).to have_received(:push).with(a_value_within(1e-12).of(0.6)).ordered
        expect(output).to have_received(:push).with(a_value_within(1e-12).of(0.3)).ordered
      end
    end

    context 'when built for the NES CPU clock' do
      subject(:resampler) { described_class.new(output_rate: 48_000, output:) }

      before { 1_789_773.times { resampler.add(0.5) } }

      it 'pushes 48 000 samples over a second of CPU cycles' do
        expect(output).to have_received(:push).exactly(48_000).times
      end
    end
  end
end
