# frozen_string_literal: true

# A channel's timer (https://www.nesdev.org/wiki/APU_Pulse): a divider that counts t, t-1, ..., 0, t, ..., and clocks
# the channel's sequencer on the transition from 0 back to t, so it clocks it every t + 1 ticks. The pulse ticks it
# every APU cycle ("every second CPU cycles"). Its period t starts at 0
# (https://www.nesdev.org/wiki/CPU_power_up_state).
RSpec.describe Ruby::Nes::Apu::Timer do
  describe '#tick' do
    context 'when the divider is above 0' do
      subject(:timer) do
        described_class.new(sequencer:).tap do |divider|
          divider.period = 2
          divider.tick
        end
      end

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'leaves the sequencer' do
        timer.tick
        expect(sequencer).to have_received(:step).once
      end
    end

    context 'when the divider is 0' do
      subject(:timer) do
        described_class.new(sequencer:).tap do |divider|
          divider.period = 2
          3.times { divider.tick }
        end
      end

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'clocks the sequencer' do
        timer.tick
        expect(sequencer).to have_received(:step).twice
      end

      it 'reloads the period', :aggregate_failures do
        timer.tick
        2.times { timer.tick }
        expect(sequencer).to have_received(:step).twice
        timer.tick
        expect(sequencer).to have_received(:step).exactly(3).times
      end
    end
  end
end
