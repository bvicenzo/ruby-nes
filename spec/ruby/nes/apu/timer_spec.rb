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

  # The sync deadline asks when a clock comes (plan 29): the next clock is on the tick that finds the counter at 0, and
  # each later one t + 1 ticks after it.
  describe '#ticks_before_clock' do
    context 'when asked for the next clock' do
      context 'and the counter is at 0' do
        subject(:timer) { described_class.new(sequencer: nil, period: 5) }

        it 'answers 0' do
          expect(timer.ticks_before_clock(1)).to eq(0)
        end
      end

      context 'and the counter is above 0' do
        subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

        let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

        it 'answers the counter' do
          expect(timer.ticks_before_clock(1)).to eq(3)
        end
      end
    end

    context 'when asked for a later clock' do
      subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'answers the counter and the period + 1 ticks of each clock between' do
        expect(timer.ticks_before_clock(3)).to eq(15)
      end
    end
  end

  # The ticks from one clock to the next, which a run of quiet cycles steps through (plan 33).
  describe '#ticks_per_clock' do
    context 'when the period is 0' do
      subject(:timer) { described_class.new(sequencer:) }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'answers 1' do
        expect(timer.ticks_per_clock).to eq(1)
      end

      it 'leaves the counter and clocks nothing', :aggregate_failures do
        timer.ticks_per_clock
        expect(timer.ticks_before_next_clock).to eq(0)
        expect(sequencer).not_to have_received(:step)
      end
    end

    context 'when the period is above 0' do
      subject(:timer) { described_class.new(sequencer:, period: 5) }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'answers the period plus 1' do
        expect(timer.ticks_per_clock).to eq(6)
      end

      it 'leaves the counter and clocks nothing', :aggregate_failures do
        timer.ticks_per_clock
        expect(timer.ticks_before_next_clock).to eq(0)
        expect(sequencer).not_to have_received(:step)
      end
    end
  end

  # A run of quiet cycles goes on until a channel's next clock (plan 29): the tick that finds the counter at 0.
  describe '#ticks_before_next_clock' do
    context 'when the counter is at 0' do
      subject(:timer) { described_class.new(sequencer: nil, period: 5) }

      it 'answers 0' do
        expect(timer.ticks_before_next_clock).to eq(0)
      end
    end

    context 'when the counter is above 0' do
      subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'answers the counter' do
        expect(timer.ticks_before_next_clock).to eq(3)
      end
    end
  end

  # A run of quiet cycles skips ticks at once (plan 29): `skip(ticks)` leaves the timer and its sequencer as that many
  # ticks would. The examples start with the period at 5 and the counter at 3, the sequencer clocked once.
  describe '#skip' do
    context 'when no tick passes' do
      subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'changes nothing', :aggregate_failures do
        timer.skip(0)
        expect(sequencer).to have_received(:step).once
        expect(timer.ticks_before_clock(1)).to eq(3)
      end
    end

    context 'when the ticks end before the counter reaches 0' do
      subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'counts down without clocking the sequencer', :aggregate_failures do
        timer.skip(2)
        expect(sequencer).to have_received(:step).once
        expect(timer.ticks_before_clock(1)).to eq(1)
      end
    end

    context 'when the ticks end with the counter at 0' do
      subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'leaves the clock to the next tick', :aggregate_failures do
        timer.skip(3)
        expect(sequencer).to have_received(:step).once
        expect(timer.ticks_before_clock(1)).to eq(0)
      end
    end

    context 'when the last tick finds the counter at 0' do
      subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'clocks the sequencer once and reloads the period', :aggregate_failures do
        timer.skip(4)
        expect(sequencer).to have_received(:step).twice
        expect(timer.ticks_before_clock(1)).to eq(5)
      end
    end

    context 'when the ticks span several periods' do
      subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'clocks the sequencer on each reload', :aggregate_failures do
        timer.skip(18)
        expect(sequencer).to have_received(:step).exactly(4).times
        expect(timer.ticks_before_clock(1)).to eq(3)
      end
    end
  end

  # A stopped triangle's clocks change nothing (plan 29), so its runs move the counter without one call per clock. The
  # examples start with the counter at 3 and the sequencer clocked once.
  describe '#skip_without_clocking' do
    context 'when the ticks end before the counter reloads' do
      subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'counts down', :aggregate_failures do
        timer.skip_without_clocking(3)
        expect(timer.ticks_before_clock(1)).to eq(0)
        expect(sequencer).to have_received(:step).once
      end
    end

    context 'when the ticks cross reloads' do
      subject(:timer) { described_class.new(sequencer:, period: 5).tap { |divider| 3.times { divider.tick } } }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'leaves the counter where they would, without clocking the sequencer', :aggregate_failures do
        timer.skip_without_clocking(18)
        expect(timer.ticks_before_clock(1)).to eq(3)
        expect(sequencer).to have_received(:step).once
      end
    end

    context 'when the period is 0' do
      subject(:timer) { described_class.new(sequencer:).tap(&:tick) }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, step: nil) }

      it 'leaves the counter at 0' do
        timer.skip_without_clocking(29_780)
        expect(timer.ticks_before_clock(1)).to eq(0)
      end
    end
  end
end
