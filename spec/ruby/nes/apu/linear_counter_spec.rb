# frozen_string_literal: true

# The triangle's linear counter (https://www.nesdev.org/wiki/APU_Triangle). $4008 is `CRRR RRRR`: bit 7 the "Linear
# counter control flag", bits 6-0 the "Linear counter reload value"; a $400B write "sets linear counter reload flag".
# On a quarter frame: "If the linear counter reload flag is set, the counter is reloaded with the counter reload value,
# otherwise, if the counter is non-zero, it is decremented", then "If the counter control flag (C bit) is clear, the
# reload flag is cleared". The triangle's sequencer runs only while it is above 0.
RSpec.describe Ruby::Nes::Apu::LinearCounter do
  describe '#write' do
    context 'when the counter is 0' do
      subject(:linear_counter) { described_class.new }

      it 'leaves it at 0 until a clock reloads it' do
        linear_counter.write(0x05)
        expect(linear_counter.count).to eq(0)
      end
    end
  end

  describe '#clock' do
    context 'when the reload flag is set' do
      context 'and the control flag is set' do
        subject(:linear_counter) do
          described_class.new.tap do |counter|
            counter.write(0x85)
            counter.restart
          end
        end

        it 'reloads the counter on every clock', :aggregate_failures do
          linear_counter.clock
          expect(linear_counter.count).to eq(5)
          linear_counter.clock
          expect(linear_counter.count).to eq(5)
        end
      end

      context 'and the control flag is clear' do
        subject(:linear_counter) do
          described_class.new.tap do |counter|
            counter.write(0x05)
            counter.restart
          end
        end

        it 'reloads the counter once, then counts down from it', :aggregate_failures do
          linear_counter.clock
          expect(linear_counter.count).to eq(5)
          linear_counter.clock
          expect(linear_counter.count).to eq(4)
        end
      end
    end

    context 'when the reload flag is clear' do
      context 'and the counter is 0' do
        subject(:linear_counter) { described_class.new.tap { |counter| counter.write(0x05) } }

        it 'keeps it at 0' do
          linear_counter.clock
          expect(linear_counter.count).to eq(0)
        end
      end

      context 'and the counter is above 0' do
        subject(:linear_counter) do
          described_class.new.tap do |counter|
            counter.write(0x05)
            counter.restart
            counter.clock
          end
        end

        it 'decrements it' do
          linear_counter.clock
          expect(linear_counter.count).to eq(4)
        end
      end
    end
  end

  describe '#active?' do
    context 'when the counter is 0' do
      subject(:linear_counter) { described_class.new }

      it { is_expected.not_to be_active }
    end

    context 'when the counter is above 0' do
      subject(:linear_counter) do
        described_class.new.tap do |counter|
          counter.write(0x01)
          counter.restart
          counter.clock
        end
      end

      it { is_expected.to be_active }
    end
  end
end
