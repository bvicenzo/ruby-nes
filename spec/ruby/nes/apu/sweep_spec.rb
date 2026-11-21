# frozen_string_literal: true

# The timer is never ticked here, so it needs no sequencer.
#
# A pulse channel's sweep unit (https://www.nesdev.org/wiki/APU_Sweep, served by the APU Pulse page), written through
# the second register, `EPPP NSSS` (enabled, divider period, negate, shift); a write sets the reload flag. The target
# period is the timer's period plus the change, the period shifted right by S, negated when N is set: pulse 1 with
# ones' complement ("Making 20 negative produces a change amount of −21"), pulse 2 with two's complement (−20). It mutes
# the channel when the period is below 8 or the target is above $7FF, and "This muting happens regardless of the state
# of the sweep unit". On a half frame clock: if the divider is 0, the sweep is enabled, the shift is not 0 and the
# channel is not muted, the period becomes the target; then, if the divider is 0 or the reload flag is set, the divider
# reloads with P and the flag clears, otherwise it decrements.
RSpec.describe Ruby::Nes::Apu::Sweep do
  describe '#muting?' do
    context 'when the period is below 8' do
      subject(:sweep) { described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT) }

      let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 7 } }

      it { is_expected.to be_muting }
    end

    context 'when the period is 8 or above' do
      context 'and the target is above $7FF' do
        context 'and the sweep is disabled' do
          subject(:sweep) do
            described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap { |unit| unit.write(0x01) }
          end

          let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x556 } }

          it { is_expected.to be_muting }
        end

        context 'and the sweep is enabled' do
          subject(:sweep) do
            described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap { |unit| unit.write(0x81) }
          end

          let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x556 } }

          it { is_expected.to be_muting }
        end
      end

      context 'and the target is $7FF' do
        subject(:sweep) do
          described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap { |unit| unit.write(0x81) }
        end

        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x555 } }

        it { is_expected.not_to be_muting }
      end

      context 'and the target is below $7FF' do
        subject(:sweep) do
          described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap { |unit| unit.write(0x81) }
        end

        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 8 } }

        it { is_expected.not_to be_muting }
      end
    end
  end

  describe '#clock' do
    context 'when the divider is above 0' do
      context 'and the reload flag is clear' do
        # Period 2: the first clock adjusts and reloads 2, the next two count down, the fourth adjusts again.
        subject(:sweep) do
          described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap do |unit|
            unit.write(0xA1)
            unit.clock
          end
        end

        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x100 } }

        it 'decrements the divider, leaving the period', :aggregate_failures do
          2.times { sweep.clock }
          expect(timer.period).to eq(0x180)
          sweep.clock
          expect(timer.period).to eq(0x240)
        end
      end

      context 'but the reload flag is set' do
        # Period 2: adjusted and reloaded with 2, counted down to 1, then written again: the next clock reloads 2
        # instead of reaching 0, so the adjustment waits three clocks.
        subject(:sweep) do
          described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap do |unit|
            unit.write(0xA1)
            unit.clock
            unit.clock
            unit.write(0xA1)
          end
        end

        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x100 } }

        it 'reloads the divider, leaving the period', :aggregate_failures do
          3.times { sweep.clock }
          expect(timer.period).to eq(0x180)
          sweep.clock
          expect(timer.period).to eq(0x240)
        end
      end
    end

    context 'when the divider is 0' do
      context 'but the sweep is disabled' do
        subject(:sweep) do
          described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap { |unit| unit.write(0x01) }
        end

        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x100 } }

        it 'leaves the period' do
          sweep.clock
          expect(timer.period).to eq(0x100)
        end
      end

      context 'but the shift is 0' do
        subject(:sweep) do
          described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap { |unit| unit.write(0x80) }
        end

        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x100 } }

        it 'leaves the period' do
          sweep.clock
          expect(timer.period).to eq(0x100)
        end
      end

      context 'but the channel is muted' do
        subject(:sweep) do
          described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap { |unit| unit.write(0x81) }
        end

        let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x556 } }

        it 'leaves the period' do
          sweep.clock
          expect(timer.period).to eq(0x556)
        end
      end

      context 'and the sweep is enabled with a shift, on a channel not muted' do
        context 'and the change is added' do
          subject(:sweep) do
            described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap { |unit| unit.write(0x82) }
          end

          let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x100 } }

          it 'adds the period shifted right to it' do
            sweep.clock
            expect(timer.period).to eq(0x140)
          end
        end

        context 'and the change is negated with ones\' complement' do
          subject(:sweep) do
            described_class.new(timer:, negation: described_class::ONES_COMPLEMENT).tap { |unit| unit.write(0x8A) }
          end

          let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x100 } }

          it 'subtracts the period shifted right and 1' do
            sweep.clock
            expect(timer.period).to eq(0x0BF)
          end
        end

        context 'and the change is negated with two\'s complement' do
          subject(:sweep) do
            described_class.new(timer:, negation: described_class::TWOS_COMPLEMENT).tap { |unit| unit.write(0x8A) }
          end

          let(:timer) { Ruby::Nes::Apu::Timer.new(sequencer: nil).tap { |divider| divider.period = 0x100 } }

          it 'subtracts the period shifted right' do
            sweep.clock
            expect(timer.period).to eq(0x0C0)
          end
        end
      end
    end
  end
end
