# frozen_string_literal: true

# The triangle channel (https://www.nesdev.org/wiki/APU_Triangle), its registers numbered 0-3 from its first address
# ($4008-$400B): `CRRR RRRR` (the linear counter, whose control flag C is also the "length counter halt flag"), an
# unused register, `TTTT TTTT` (timer low) and `LLLL LTTT` (length counter load and timer high), whose write "sets
# linear counter reload flag too". "The sequencer is clocked by the timer as long as both the linear counter and the
# length counter are nonzero"; the timer "ticks at the rate of the CPU clock". Quarter frames clock the linear counter,
# half frames the length counter; $4015 enables it. The channel outputs the sequencer's value whether it runs or not.
# Periods below 2 are played as any other (plan 23, decision 4). After reset the "Triangle phase" is 0
# (https://www.nesdev.org/wiki/CPU_power_up_state).
RSpec.describe Ruby::Nes::Apu::Triangle do
  describe '#write' do
    context 'when the register is the first' do
      context 'and the control flag is set' do
        subject(:channel) { described_class.new(linear_counter:, length_counter:) }

        let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, write: nil) }
        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, :halted= => nil) }

        before { channel.write(0, 0x81) }

        it 'writes the linear counter and halts the length counter', :aggregate_failures do
          expect(linear_counter).to have_received(:write).with(0x81)
          expect(length_counter).to have_received(:halted=).with(true)
        end
      end

      context 'and the control flag is clear' do
        subject(:channel) { described_class.new(linear_counter:, length_counter:) }

        let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, write: nil) }
        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, :halted= => nil) }

        before { channel.write(0, 0x01) }

        it 'writes the linear counter and lets the length counter run', :aggregate_failures do
          expect(linear_counter).to have_received(:write).with(0x01)
          expect(length_counter).to have_received(:halted=).with(false)
        end
      end
    end

    context 'when the register is the second' do
      subject(:channel) { described_class.new(linear_counter:, length_counter:, timer:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter) }
      let(:timer) { instance_double(Ruby::Nes::Apu::Timer) }

      it 'changes nothing' do
        expect { channel.write(1, 0xFF) }.not_to raise_error
      end
    end

    context 'when the register is the third' do
      subject(:channel) { described_class.new(timer:) }

      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, write_period_low: nil) }

      it 'sets the low 8 bits of the period' do
        channel.write(2, 0x34)
        expect(timer).to have_received(:write_period_low).with(0x34)
      end
    end

    context 'when the register is the fourth' do
      subject(:channel) { described_class.new(linear_counter:, length_counter:, timer:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, restart: nil) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, load: nil) }
      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, write_period_high: nil) }

      before { channel.write(3, 0xFA) }

      it 'sets the high 3 bits of the period, loads the length counter and sets the reload flag', :aggregate_failures do
        expect(timer).to have_received(:write_period_high).with(0xFA)
        expect(length_counter).to have_received(:load).with(0xFA)
        expect(linear_counter).to have_received(:restart)
      end
    end
  end

  describe '#tick_timer' do
    context 'when a CPU cycle passes' do
      subject(:channel) { described_class.new(timer:) }

      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, tick: nil) }

      it 'ticks the timer' do
        channel.tick_timer
        expect(timer).to have_received(:tick)
      end
    end
  end

  # What the timer clocks.
  describe '#step' do
    context 'when the linear counter is 0' do
      subject(:channel) { described_class.new(linear_counter:, length_counter:, sequencer:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: false) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
      let(:sequencer) { instance_double(Ruby::Nes::Apu::TriangleSequencer, step: nil) }

      it 'leaves the sequencer on its step' do
        channel.step
        expect(sequencer).not_to have_received(:step)
      end
    end

    context 'when the linear counter is above 0' do
      context 'but the length counter is 0' do
        subject(:channel) { described_class.new(linear_counter:, length_counter:, sequencer:) }

        let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: true) }
        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: false) }
        let(:sequencer) { instance_double(Ruby::Nes::Apu::TriangleSequencer, step: nil) }

        it 'leaves the sequencer on its step' do
          channel.step
          expect(sequencer).not_to have_received(:step)
        end
      end

      context 'and the length counter is above 0' do
        subject(:channel) { described_class.new(linear_counter:, length_counter:, sequencer:) }

        let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: true) }
        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
        let(:sequencer) { instance_double(Ruby::Nes::Apu::TriangleSequencer, step: nil) }

        it 'steps the sequencer' do
          channel.step
          expect(sequencer).to have_received(:step)
        end
      end
    end
  end

  describe '#quarter_frame' do
    context 'when the frame counter clocks it' do
      subject(:channel) { described_class.new(linear_counter:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, clock: nil) }

      it 'clocks the linear counter' do
        channel.quarter_frame
        expect(linear_counter).to have_received(:clock)
      end
    end
  end

  describe '#half_frame' do
    context 'when the frame counter clocks it' do
      subject(:channel) { described_class.new(length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, clock: nil) }

      it 'clocks the length counter' do
        channel.half_frame
        expect(length_counter).to have_received(:clock)
      end
    end
  end

  describe '#enabled=' do
    context 'when $4015 disables the channel' do
      subject(:channel) { described_class.new(length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, :enabled= => nil) }

      it 'disables the length counter' do
        channel.enabled = false
        expect(length_counter).to have_received(:enabled=).with(false)
      end
    end
  end

  describe '#active?' do
    context 'when the length counter is above 0' do
      subject(:channel) { described_class.new(length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }

      it { is_expected.to be_active }
    end
  end

  describe '#output' do
    context 'when the sequencer stands on a step' do
      subject(:channel) { described_class.new(sequencer:) }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::TriangleSequencer, output: 9) }

      it "is that step's value" do
        expect(channel.output).to eq(9)
      end
    end
  end

  describe '#reset' do
    context 'when the reset button is pressed' do
      subject(:channel) { described_class.new(sequencer:) }

      let(:sequencer) { instance_double(Ruby::Nes::Apu::TriangleSequencer, reset: nil) }

      it 'puts the sequencer back on its first step' do
        channel.reset
        expect(sequencer).to have_received(:reset)
      end
    end
  end

  # A run of quiet cycles goes on until a channel's output can change (plan 29): the timer steps the sequencer only
  # while both counters are above 0, and they change only on frame counter steps and register writes.
  describe '#quiet_ticks' do
    context 'when the linear counter is 0' do
      subject(:channel) { described_class.new(linear_counter:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: false) }

      it 'answers never' do
        expect(channel.quiet_ticks).to eq(Ruby::Nes::Apu::NEVER)
      end
    end

    context 'when the linear counter is above 0' do
      context 'but the length counter is 0' do
        subject(:channel) { described_class.new(linear_counter:, length_counter:) }

        let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: true) }
        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: false) }

        it 'answers never' do
          expect(channel.quiet_ticks).to eq(Ruby::Nes::Apu::NEVER)
        end
      end

      context 'and the length counter is above 0' do
        subject(:channel) { described_class.new(linear_counter:, length_counter:, timer:) }

        let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: true) }
        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
        let(:timer) { instance_double(Ruby::Nes::Apu::Timer, ticks_before_next_clock: 40) }

        it "answers the timer's ticks before its next clock", :aggregate_failures do
          expect(channel.quiet_ticks).to eq(40)
          expect(timer).to have_received(:ticks_before_next_clock)
        end
      end
    end
  end

  # A stopped sequencer's clocks change nothing, so its timer skips the ticks without one call per clock (plan 29).
  describe '#skip' do
    context 'when a counter at 0 stops the sequencer' do
      subject(:channel) { described_class.new(linear_counter:, timer:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: false) }
      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, skip_without_clocking: nil) }

      it "skips the timer's ticks without clocking the sequencer" do
        channel.skip(25)
        expect(timer).to have_received(:skip_without_clocking).with(25)
      end
    end

    context 'when both counters are above 0' do
      subject(:channel) { described_class.new(linear_counter:, length_counter:, timer:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: true) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, skip: nil) }

      it "skips the timer's ticks, clocking the sequencer on each reload" do
        channel.skip(25)
        expect(timer).to have_received(:skip).with(25)
      end
    end
  end

  # A quiet run of the other units steps the triangle clock by clock (plan 33): its clocks come every
  # `ticks_per_clock` ticks, and after them the timer moves on through the run without clocking the sequencer again.
  describe '#ticks_per_clock' do
    context 'when a counter at 0 stops the sequencer' do
      subject(:channel) { described_class.new(linear_counter:, timer:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: false) }
      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, ticks_per_clock: 7) }

      it "answers its timer's ticks per clock" do
        expect(channel.ticks_per_clock).to eq(7)
      end
    end

    context 'when both counters are above 0' do
      subject(:channel) { described_class.new(linear_counter:, length_counter:, timer:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: true) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, ticks_per_clock: 7) }

      it "answers its timer's ticks per clock" do
        expect(channel.ticks_per_clock).to eq(7)
      end
    end
  end

  describe '#skip_without_clocking' do
    context 'when a counter at 0 stops the sequencer' do
      subject(:channel) { described_class.new(linear_counter:, sequencer:, timer:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: false) }
      let(:sequencer) { instance_double(Ruby::Nes::Apu::TriangleSequencer, step: nil) }
      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, skip_without_clocking: nil, skip: nil) }

      it 'moves its timer on the ticks without clocking the sequencer', :aggregate_failures do
        channel.skip_without_clocking(25)
        expect(timer).to have_received(:skip_without_clocking).with(25)
        expect(timer).not_to have_received(:skip)
        expect(sequencer).not_to have_received(:step)
      end
    end

    context 'when both counters are above 0' do
      subject(:channel) { described_class.new(linear_counter:, length_counter:, sequencer:, timer:) }

      let(:linear_counter) { instance_double(Ruby::Nes::Apu::LinearCounter, active?: true) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
      let(:sequencer) { instance_double(Ruby::Nes::Apu::TriangleSequencer, step: nil) }
      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, skip_without_clocking: nil, skip: nil) }

      it 'moves its timer on the ticks without clocking the sequencer', :aggregate_failures do
        channel.skip_without_clocking(25)
        expect(timer).to have_received(:skip_without_clocking).with(25)
        expect(timer).not_to have_received(:skip)
        expect(sequencer).not_to have_received(:step)
      end
    end
  end
end
