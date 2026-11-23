# frozen_string_literal: true

# The CPU cycles the pulse, noise and DMC timers tick on, once per APU cycle: "2 CPU cycles = 1 APU cycle"
# (https://www.nesdev.org/wiki/APU_Frame_Counter), with even cycles as get cycles (plan 22, decision 5). The sync
# deadline and the runs count those ticks in CPU cycles (plan 29).
RSpec.describe Ruby::Nes::Apu::GetCycles do
  describe '.cycle_of_tick' do
    context 'when counting from a get cycle' do
      context 'and it asks for the first tick' do
        it 'answers that cycle' do
          expect(described_class.cycle_of_tick(100, 0)).to eq(100)
        end
      end

      context 'and it asks for a later tick' do
        it 'answers two cycles per tick after it' do
          expect(described_class.cycle_of_tick(100, 3)).to eq(106)
        end
      end
    end

    context 'when counting from a put cycle' do
      context 'and it asks for the first tick' do
        it 'answers the next cycle' do
          expect(described_class.cycle_of_tick(101, 0)).to eq(102)
        end
      end

      context 'and it asks for a later tick' do
        it 'answers two cycles per tick after the next one' do
          expect(described_class.cycle_of_tick(101, 3)).to eq(108)
        end
      end
    end
  end

  describe '.count' do
    context 'when no cycle passes' do
      it 'answers 0' do
        expect(described_class.count(101, 0)).to eq(0)
      end
    end

    context 'when cycles pass' do
      context 'and they start on a get cycle' do
        context 'and their number is even' do
          it 'answers half of them' do
            expect(described_class.count(100, 4)).to eq(2)
          end
        end

        context 'and their number is odd' do
          it 'answers half of them rounded up' do
            expect(described_class.count(100, 5)).to eq(3)
          end
        end
      end

      context 'and they start on a put cycle' do
        context 'and their number is even' do
          it 'answers half of them' do
            expect(described_class.count(101, 4)).to eq(2)
          end
        end

        context 'and their number is odd' do
          it 'answers half of them rounded down' do
            expect(described_class.count(101, 5)).to eq(2)
          end
        end
      end
    end
  end
end
