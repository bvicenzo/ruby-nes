# frozen_string_literal: true

# The NES's output circuit for each resampled level (plan 24, decision 5): "A first-order high-pass filter at 90 Hz",
# then "A first-order low-pass filter at 14 kHz" (https://www.nesdev.org/wiki/APU_Mixer); then a signed 16-bit sample,
# full scale 32 767, into the frame's samples. A level of 0.0-1.0 leaves the high-pass within (-1, 1) and the low-pass
# never overshoots, so the sample needs no clamping.
RSpec.describe Ruby::Nes::Audio::OutputStage do
  describe '#push' do
    let(:samples) { instance_double(Ruby::Nes::Audio::SampleBuffer, push: nil) }

    context 'when it builds the NES filters' do
      subject(:stage) { described_class.new(samples:, sample_rate: 48_000) }

      # From rest, a step of `level` comes out of the high-pass at alpha × level and out of the low-pass at beta × that,
      # alpha = RC / (RC + dt) at 90 Hz and beta = dt / (RC + dt) at 14 kHz, RC = 1 / (2π × cut-off), dt = 1 / 48 000.
      let(:sample_period) { 1.0 / 48_000 }
      let(:high_pass_time_constant) { 1 / (2 * Math::PI * 90) }
      let(:low_pass_time_constant) { 1 / (2 * Math::PI * 14_000) }
      let(:alpha) { high_pass_time_constant / (high_pass_time_constant + sample_period) }
      let(:beta) { sample_period / (low_pass_time_constant + sample_period) }

      it 'high-passes the level at 90 Hz, then low-passes it at 14 kHz' do
        stage.push(0.3)

        expect(samples).to have_received(:push).with((0.3 * alpha * beta * 32_767).round)
      end
    end

    context 'when it is given filters' do
      subject(:stage) { described_class.new(samples:, high_pass:, low_pass:) }

      let(:high_pass) { instance_double(Ruby::Nes::Audio::HighPassFilter) }
      let(:low_pass) { instance_double(Ruby::Nes::Audio::LowPassFilter) }

      before do
        allow(high_pass).to receive(:filter).with(0.3).and_return(-0.25)
        allow(low_pass).to receive(:filter).with(-0.25).and_return(-0.5)
      end

      it 'pushes the high-passed, then low-passed level, scaled to 16 bits and rounded' do
        stage.push(0.3)

        expect(samples).to have_received(:push).with(-16_384)
      end
    end
  end
end
