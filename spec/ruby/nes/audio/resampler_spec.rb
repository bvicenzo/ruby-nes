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

  # A run of quiet cycles hands the resampler one level for many cycles (plan 29): it must give the samples as many
  # `add` calls would, to the last bit of the float sum. With an input rate of 10 and an output rate of 3, samples are
  # due after cycles 4, 7, 10 and 14.
  describe '#add_run' do
    context 'when no cycle passes' do
      subject(:resampler) { described_class.new(output_rate: 3, output:, input_rate: 10) }

      let(:output) { instance_double(Ruby::Nes::Audio::OutputStage, push: nil) }

      before do
        resampler.add_run(0.5, 0)
        4.times { resampler.add(1.0) }
      end

      it 'adds nothing' do
        expect(output).to have_received(:push).once.with(1.0)
      end
    end

    context 'when the run ends before a sample is due' do
      subject(:resampler) { described_class.new(output_rate: 3, output:, input_rate: 10) }

      let(:output) { instance_double(Ruby::Nes::Audio::OutputStage, push: nil) }

      before { resampler.add_run(0.5, 3) }

      it "pushes nothing and counts the run in the next sample's mean", :aggregate_failures do
        expect(output).not_to have_received(:push)
        resampler.add(1.0)
        expect(output).to have_received(:push).once.with(0.625)
      end
    end

    context 'when the run ends on the cycle a sample is due' do
      subject(:resampler) { described_class.new(output_rate: 3, output:, input_rate: 10) }

      let(:output) { instance_double(Ruby::Nes::Audio::OutputStage, push: nil) }

      before { resampler.add_run(0.5, 4) }

      it "pushes the period's mean" do
        expect(output).to have_received(:push).once.with(0.5)
      end
    end

    context 'when the run crosses the end of a sample' do
      subject(:resampler) { described_class.new(output_rate: 3, output:, input_rate: 10) }

      let(:output) { Ruby::Nes::Audio::SampleBuffer.new }

      before do
        2.times { resampler.add(1.0) }
        resampler.add_run(0.5, 4)
        resampler.add(0.0)
      end

      it 'splits it there, the rest counting in the next sample' do
        expect(output.drain).to eq([0.75, 1.0 / 3])
      end
    end

    context 'when the output rate is above the input rate' do
      subject(:resampler) { described_class.new(output_rate: 4, output:, input_rate: 2) }

      let(:output) { Ruby::Nes::Audio::SampleBuffer.new }

      before { 2.times { resampler.add_run(0.5, 1) } }

      it 'pushes a sample for every cycle, as add does' do
        expect(output.drain).to eq([0.5, 0.5])
      end
    end

    context 'when the run spans several samples' do
      subject(:resampler) { described_class.new(output_rate: 3, output:, input_rate: 10) }

      let(:output) { Ruby::Nes::Audio::SampleBuffer.new }
      let(:cycle_by_cycle) { described_class.new(output_rate: 3, output: cycle_by_cycle_output, input_rate: 10) }
      let(:cycle_by_cycle_output) { Ruby::Nes::Audio::SampleBuffer.new }

      # After 0.7, adding 0.1 three times gives 0.9999999999999999, adding 0.3 gives 1.0.
      before do
        resampler.add(0.7)
        resampler.add_run(0.1, 13)
        cycle_by_cycle.add(0.7)
        13.times { cycle_by_cycle.add(0.1) }
      end

      it 'pushes the samples as many adds would, to the last bit', :aggregate_failures do
        levels = output.drain
        expect(levels.size).to eq(4)
        expect(levels).to eq(cycle_by_cycle_output.drain)
      end
    end
  end
end
