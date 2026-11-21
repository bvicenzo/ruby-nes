# frozen_string_literal: true

# A channel's envelope (https://www.nesdev.org/wiki/APU_Envelope), written through the low six bits of its first
# register, `--LC VVVV`: the loop flag L, the constant volume flag C and V, the volume or the divider's reload value
# ("the period becomes V + 1 quarter frames"). On a quarter frame clock: if the start flag is set, it clears, the decay
# level becomes 15 and the divider reloads; otherwise the divider is clocked, and when it is 0 it reloads with V and
# clocks the decay level, which decrements, or becomes 15 at 0 when the loop flag is set. The volume is V when C is set,
# the decay level otherwise; "the decay level will still be updated". A write to the channel's fourth register sets the
# start flag.
RSpec.describe Ruby::Nes::Apu::Envelope do
  describe '#clock' do
    context 'when the start flag is set' do
      subject(:envelope) do
        described_class.new.tap do |unit|
          unit.write(0x01)
          unit.restart
        end
      end

      it 'sets the decay level to 15 and reloads the divider', :aggregate_failures do
        envelope.clock
        expect(envelope.volume).to eq(15)
        envelope.clock
        expect(envelope.volume).to eq(15)
        envelope.clock
        expect(envelope.volume).to eq(14)
      end
    end

    context 'when the start flag is clear' do
      context 'and the divider is above 0' do
        subject(:envelope) do
          described_class.new.tap do |unit|
            unit.write(0x02)
            unit.restart
            unit.clock
          end
        end

        it 'keeps the decay level' do
          envelope.clock
          expect(envelope.volume).to eq(15)
        end
      end

      context 'and the divider is 0' do
        context 'and the decay level is above 0' do
          subject(:envelope) do
            described_class.new.tap do |unit|
              unit.write(0x00)
              unit.restart
              unit.clock
            end
          end

          it 'decrements the decay level' do
            envelope.clock
            expect(envelope.volume).to eq(14)
          end
        end

        context 'and the decay level is 0' do
          context 'but the loop flag is clear' do
            subject(:envelope) do
              described_class.new.tap do |unit|
                unit.write(0x00)
                unit.restart
                16.times { unit.clock }
              end
            end

            it 'keeps the decay level at 0' do
              envelope.clock
              expect(envelope.volume).to eq(0)
            end
          end

          context 'and the loop flag is set' do
            subject(:envelope) do
              described_class.new.tap do |unit|
                unit.write(0x20)
                unit.restart
                16.times { unit.clock }
              end
            end

            it 'sets the decay level to 15' do
              envelope.clock
              expect(envelope.volume).to eq(15)
            end
          end
        end
      end
    end
  end

  describe '#volume' do
    context 'when the constant volume flag is clear' do
      subject(:envelope) do
        described_class.new.tap do |unit|
          unit.write(0x07)
          unit.restart
          unit.clock
        end
      end

      it 'returns the decay level' do
        expect(envelope.volume).to eq(15)
      end
    end

    context 'when the constant volume flag is set' do
      subject(:envelope) do
        described_class.new.tap do |unit|
          unit.write(0x17)
          unit.restart
          unit.clock
        end
      end

      it 'returns V' do
        expect(envelope.volume).to eq(7)
      end
    end
  end
end
