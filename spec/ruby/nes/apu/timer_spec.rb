# frozen_string_literal: true

# A channel's timer (https://www.nesdev.org/wiki/APU_Pulse): a divider that counts t, t-1, ..., 0, t, ..., and clocks
# the channel's sequencer on the transition from 0 back to t, so it clocks it every t + 1 ticks. The pulse ticks it
# every APU cycle ("every second CPU cycles"). Its period t starts at 0
# (https://www.nesdev.org/wiki/CPU_power_up_state). The pulse and triangle channels write t through two registers:
# `TTTT TTTT`, its low 8 bits, and `LLLL LTTT`, whose bits 2-0 are its high 3 bits (https://www.nesdev.org/wiki/APU).
RSpec.describe Ruby::Nes::Apu::Timer do
  # The noise and DMC tables are in CPU cycles, and their timers are clocked "only on every second CPU cycle"
  # (https://www.nesdev.org/wiki/APU): a timer that counts its reload value down to 0 reloads half the period minus 1.
  describe '.reload_for' do
    context "when the period is the noise's shortest, 4 CPU cycles" do
      it 'is 1' do
        expect(described_class.reload_for(4)).to eq(1)
      end
    end

    context "when the period is the DMC's longest, 428 CPU cycles" do
      it 'is 213' do
        expect(described_class.reload_for(428)).to eq(213)
      end
    end
  end

  describe '.new' do
    context 'when no period is given' do
      it 'starts at period 0' do
        expect(described_class.new(sequencer: nil).period).to eq(0)
      end
    end

    context 'when a period is given' do
      it 'starts at that period' do
        expect(described_class.new(sequencer: nil, period: 213).period).to eq(213)
      end
    end
  end

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

  describe '#write_period_low' do
    context 'when the period has high bits' do
      subject(:timer) { described_class.new(sequencer: nil).tap { |divider| divider.period = 0x5FF } }

      it 'replaces only its low 8 bits' do
        timer.write_period_low(0x34)
        expect(timer.period).to eq(0x534)
      end
    end
  end

  describe '#write_period_high' do
    context 'when the period has low bits' do
      subject(:timer) { described_class.new(sequencer: nil).tap { |divider| divider.period = 0x734 } }

      it 'replaces its high 3 bits with the low 3 bits of the value' do
        timer.write_period_high(0xFA)
        expect(timer.period).to eq(0x234)
      end
    end
  end
end
