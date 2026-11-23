# frozen_string_literal: true

# The noise channel (https://www.nesdev.org/wiki/APU_Noise), its registers numbered 0-3 from its first address
# ($400C-$400F): `--LC VVVV` (the "Length counter halt flag and envelope loop flag", constant volume, volume), an unused
# register, `M--- PPPP` ("Periodic noise mode" and the period index) and `LLLL L---` (length counter load), which "also
# restarts envelope". The NTSC periods are "CPU cycles between shift register clocks", 4, 8, 16, 32, 64, 96, 128, 160,
# 202, 254, 380, 508, 762, 1016, 2034, 4068; the noise timer "only on every second CPU cycle"
# (https://www.nesdev.org/wiki/APU), so it reloads half the period minus 1 in APU cycles. The timer clocks the shift
# register; quarter frames clock the envelope, half frames the length counter; $4015 enables it. The output is the
# envelope's volume "except when bit 0 of the shift register is set, or the length counter is zero".
RSpec.describe Ruby::Nes::Apu::Noise do
  # $400E is 0 at power (https://www.nesdev.org/wiki/CPU_power_up_state): the first period, 4 CPU cycles, 2 APU cycles
  # between shift register clocks.
  describe '.new' do
    context 'when the console powers up' do
      let(:shift_register) { instance_double(Ruby::Nes::Apu::NoiseShiftRegister, step: nil) }

      it 'runs the timer at the first period', :aggregate_failures do
        noise = described_class.new(shift_register:)
        2.times { noise.tick_timer }
        expect(shift_register).to have_received(:step).once
        noise.tick_timer
        expect(shift_register).to have_received(:step).twice
      end
    end
  end

  describe '#write' do
    context 'when the register is the first' do
      subject(:channel) { described_class.new(envelope:, length_counter:) }

      let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, write: nil) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, :halted= => nil) }

      before { channel.write(0, 0x3A) }

      it 'writes the envelope and the length counter halt', :aggregate_failures do
        expect(envelope).to have_received(:write).with(0x3A)
        expect(length_counter).to have_received(:halted=).with(true)
      end
    end

    context 'when the register is the second' do
      subject(:channel) { described_class.new(envelope:, length_counter:, shift_register:, timer:) }

      let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter) }
      let(:shift_register) { instance_double(Ruby::Nes::Apu::NoiseShiftRegister) }
      let(:timer) { instance_double(Ruby::Nes::Apu::Timer) }

      it 'changes nothing' do
        expect { channel.write(1, 0xFF) }.not_to raise_error
      end
    end

    context 'when the register is the third' do
      context 'and the mode flag is set' do
        subject(:channel) { described_class.new(shift_register:) }

        let(:shift_register) { instance_double(Ruby::Nes::Apu::NoiseShiftRegister, :periodic= => nil) }

        it 'turns periodic mode on' do
          channel.write(2, 0x80)
          expect(shift_register).to have_received(:periodic=).with(true)
        end
      end

      context 'and the mode flag is clear' do
        subject(:channel) { described_class.new(shift_register:) }

        let(:shift_register) { instance_double(Ruby::Nes::Apu::NoiseShiftRegister, :periodic= => nil) }

        it 'turns periodic mode off' do
          channel.write(2, 0x00)
          expect(shift_register).to have_received(:periodic=).with(false)
        end
      end

      context 'and the period index is the first' do
        subject(:channel) { described_class.new(timer:) }

        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil) }

        it 'sets the timer to 4 CPU cycles' do
          channel.write(2, 0x80)
          expect(timer.period).to eq(1)
        end
      end

      context 'and the period index is the last' do
        subject(:channel) { described_class.new(timer:) }

        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil) }

        it 'sets the timer to 4068 CPU cycles' do
          channel.write(2, 0x0F)
          expect(timer.period).to eq(2033)
        end
      end
    end

    context 'when the register is the fourth' do
      subject(:channel) { described_class.new(envelope:, length_counter:) }

      let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, restart: nil) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, load: nil) }

      before { channel.write(3, 0xFA) }

      it 'loads the length counter and restarts the envelope', :aggregate_failures do
        expect(length_counter).to have_received(:load).with(0xFA)
        expect(envelope).to have_received(:restart)
      end
    end
  end

  describe '#tick_timer' do
    context 'when an APU cycle passes' do
      subject(:channel) { described_class.new(timer:) }

      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, tick: nil) }

      it 'ticks the timer, which clocks the shift register' do
        channel.tick_timer
        expect(timer).to have_received(:tick)
      end
    end
  end

  describe '#quarter_frame' do
    context 'when the frame counter clocks it' do
      subject(:channel) { described_class.new(envelope:) }

      let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, clock: nil) }

      it 'clocks the envelope' do
        channel.quarter_frame
        expect(envelope).to have_received(:clock)
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
    context 'when the shift register mutes the channel' do
      subject(:channel) { described_class.new(envelope:, length_counter:, shift_register:) }

      let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, volume: 9) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
      let(:shift_register) { instance_double(Ruby::Nes::Apu::NoiseShiftRegister, muting?: true) }

      it 'is 0' do
        expect(channel.output).to eq(0)
      end
    end

    context 'when the shift register lets it sound' do
      context 'but the length counter is 0' do
        subject(:channel) { described_class.new(envelope:, length_counter:, shift_register:) }

        let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, volume: 9) }
        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: false) }
        let(:shift_register) { instance_double(Ruby::Nes::Apu::NoiseShiftRegister, muting?: false) }

        it 'is 0' do
          expect(channel.output).to eq(0)
        end
      end

      context 'and the length counter is above 0' do
        subject(:channel) { described_class.new(envelope:, length_counter:, shift_register:) }

        let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, volume: 9) }
        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
        let(:shift_register) { instance_double(Ruby::Nes::Apu::NoiseShiftRegister, muting?: false) }

        it "is the envelope's volume" do
          expect(channel.output).to eq(9)
        end
      end
    end
  end

  # A run of quiet cycles goes on until a channel's output can change (plan 29): a muted noise outputs 0 whatever its
  # shift register does, and what mutes it changes only on frame counter steps and register writes.
  describe '#quiet_ticks' do
    context 'when the length counter is 0' do
      subject(:channel) { described_class.new(length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: false) }

      it 'answers never' do
        expect(channel.quiet_ticks).to eq(Ruby::Nes::Apu::NEVER)
      end
    end

    context 'when the length counter is above 0' do
      context 'but the volume is 0' do
        subject(:channel) { described_class.new(length_counter:, envelope:) }

        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
        let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, volume: 0) }

        it 'answers never' do
          expect(channel.quiet_ticks).to eq(Ruby::Nes::Apu::NEVER)
        end
      end

      context 'and the volume is above 0' do
        subject(:channel) { described_class.new(length_counter:, envelope:, timer:) }

        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
        let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, volume: 9) }
        let(:timer) { instance_double(Ruby::Nes::Apu::Timer, ticks_before_next_clock: 40) }

        it "answers the timer's ticks before its next clock", :aggregate_failures do
          expect(channel.quiet_ticks).to eq(40)
          expect(timer).to have_received(:ticks_before_next_clock)
        end
      end
    end
  end

  describe '#skip' do
    subject(:channel) { described_class.new(timer:) }

    let(:timer) { instance_double(Ruby::Nes::Apu::Timer, skip: nil) }

    it "skips the timer's ticks" do
      channel.skip(25)
      expect(timer).to have_received(:skip).with(25)
    end
  end
end
