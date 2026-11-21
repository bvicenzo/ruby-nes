# frozen_string_literal: true

# A pulse channel (https://www.nesdev.org/wiki/APU_Pulse), its registers numbered 0-3 from its first address ($4000 or
# $4004): `DDLC VVVV` (duty, length counter halt, envelope), `EPPP NSSS` (sweep), `TTTT TTTT` (timer low) and
# `LLLL LTTT` (length counter load, timer high), whose write also "resets the sequencer index ... restart envelope".
# The timer clocks the duty sequencer; quarter frames clock the envelope, half frames the length counter and the sweep.
# The channel outputs 0 when "the sequencer output is zero", the sweep mutes it (period below 8, target above $7FF) or
# "the length counter is zero"; the envelope's volume otherwise.
RSpec.describe Ruby::Nes::Apu::Pulse do
  describe '#write' do
    context 'when the register is the first' do
      subject(:pulse) do
        described_class.new(negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, sequencer:, envelope:, length_counter:)
      end

      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, :duty= => nil) }
      let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, write: nil) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, :halted= => nil) }

      before { pulse.write(0, 0xBF) }

      it 'sets the duty, the length counter halt and the envelope', :aggregate_failures do
        expect(sequencer).to have_received(:duty=).with(2)
        expect(length_counter).to have_received(:halted=).with(true)
        expect(envelope).to have_received(:write).with(0xBF)
      end
    end

    context 'when the register is the second' do
      subject(:pulse) { described_class.new(negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, sweep:) }

      let(:sweep) { instance_double(Ruby::Nes::Apu::Sweep, write: nil) }

      before { pulse.write(1, 0x8A) }

      it 'writes the sweep' do
        expect(sweep).to have_received(:write).with(0x8A)
      end
    end

    context 'when the register is the third' do
      subject(:pulse) do
        described_class.new(negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, timer:).tap do |channel|
          channel.write(3, 0x05)
        end
      end

      let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil) }

      before { pulse.write(2, 0x34) }

      it 'sets the low 8 bits of the period' do
        expect(timer.period).to eq(0x534)
      end
    end

    context 'when the register is the fourth' do
      subject(:pulse) do
        described_class.new(
          negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, timer:, sequencer:, envelope:, length_counter:
        )
      end

      let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil) }
      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, restart: nil) }
      let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, restart: nil) }
      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, load: nil) }

      before do
        pulse.write(2, 0x34)
        pulse.write(3, 0xFA)
      end

      it 'sets the high 3 bits of the period, loads the length counter and restarts', :aggregate_failures do
        expect(timer.period).to eq(0x234)
        expect(length_counter).to have_received(:load).with(0xFA)
        expect(sequencer).to have_received(:restart)
        expect(envelope).to have_received(:restart)
      end
    end
  end

  describe '#tick_timer' do
    context 'when an APU cycle passes' do
      subject(:pulse) { described_class.new(negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, timer:) }

      let(:timer) { instance_double(Ruby::Nes::Apu::Timer, tick: nil) }

      it 'ticks the timer, which clocks the sequencer' do
        pulse.tick_timer
        expect(timer).to have_received(:tick)
      end
    end
  end

  describe '#quarter_frame' do
    context 'when the frame counter clocks it' do
      subject(:pulse) { described_class.new(negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, envelope:) }

      let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, clock: nil) }

      it 'clocks the envelope' do
        pulse.quarter_frame
        expect(envelope).to have_received(:clock)
      end
    end
  end

  describe '#half_frame' do
    context 'when the frame counter clocks it' do
      subject(:pulse) { described_class.new(negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, length_counter:, sweep:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, clock: nil) }
      let(:sweep) { instance_double(Ruby::Nes::Apu::Sweep, clock: nil) }

      it 'clocks the length counter and the sweep', :aggregate_failures do
        pulse.half_frame
        expect(length_counter).to have_received(:clock)
        expect(sweep).to have_received(:clock)
      end
    end
  end

  describe '#enabled=' do
    context 'when $4015 disables the channel' do
      subject(:pulse) { described_class.new(negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, :enabled= => nil) }

      it 'disables the length counter' do
        pulse.enabled = false
        expect(length_counter).to have_received(:enabled=).with(false)
      end
    end
  end

  describe '#active?' do
    context 'when the length counter is above 0' do
      subject(:pulse) { described_class.new(negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, length_counter:) }

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }

      it { is_expected.to be_active }
    end
  end

  describe '#output' do
    context 'when the length counter is 0' do
      subject(:pulse) do
        described_class.new(
          negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, length_counter:, sweep:, sequencer:, envelope:
        )
      end

      let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: false) }
      let(:sweep) { instance_double(Ruby::Nes::Apu::Sweep, muting?: false) }
      let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, output: 1) }
      let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, volume: 9) }

      it 'returns 0' do
        expect(pulse.output).to eq(0)
      end
    end

    context 'when the length counter is above 0' do
      context 'but the sweep mutes the channel' do
        subject(:pulse) do
          described_class.new(
            negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, length_counter:, sweep:, sequencer:, envelope:
          )
        end

        let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
        let(:sweep) { instance_double(Ruby::Nes::Apu::Sweep, muting?: true) }
        let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, output: 1) }
        let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, volume: 9) }

        it 'returns 0' do
          expect(pulse.output).to eq(0)
        end
      end

      context 'and the sweep does not mute it' do
        context 'but the sequencer outputs 0' do
          subject(:pulse) do
            described_class.new(
              negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, length_counter:, sweep:, sequencer:, envelope:
            )
          end

          let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
          let(:sweep) { instance_double(Ruby::Nes::Apu::Sweep, muting?: false) }
          let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, output: 0) }
          let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, volume: 9) }

          it 'returns 0' do
            expect(pulse.output).to eq(0)
          end
        end

        context 'and the sequencer outputs 1' do
          subject(:pulse) do
            described_class.new(
              negation: Ruby::Nes::Apu::Sweep::ONES_COMPLEMENT, length_counter:, sweep:, sequencer:, envelope:
            )
          end

          let(:length_counter) { instance_double(Ruby::Nes::Apu::LengthCounter, active?: true) }
          let(:sweep) { instance_double(Ruby::Nes::Apu::Sweep, muting?: false) }
          let(:sequencer) { instance_double(Ruby::Nes::Apu::DutySequencer, output: 1) }
          let(:envelope) { instance_double(Ruby::Nes::Apu::Envelope, volume: 9) }

          it 'returns the envelope volume' do
            expect(pulse.output).to eq(9)
          end
        end
      end
    end
  end
end
