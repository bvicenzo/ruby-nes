# frozen_string_literal: true

# A channel's length counter (https://www.nesdev.org/wiki/APU_Length_Counter). "If the enabled flag is set, the length
# counter is loaded with entry L of the length table" (10, 254, 20, 2, … 30), L being bits 7-3 of the channel's fourth
# register (`LLLL L---`, https://www.nesdev.org/wiki/APU), which `load` is given whole; a half frame clock decrements it
# unless it is 0 or the halt flag is set; "When the enabled bit is cleared (via $4015), the length counter is forced to
# 0 and cannot be changed until enabled is set again", and enabling "has no immediate effect". The channel sounds while
# it is above 0, which $4015 reports. It starts disabled, at 0 (https://www.nesdev.org/wiki/CPU_power_up_state).
RSpec.describe Ruby::Nes::Apu::LengthCounter do
  describe '#load' do
    context 'when the channel is disabled' do
      subject(:length_counter) { described_class.new }

      it 'keeps the counter at 0' do
        length_counter.load(0x08)
        expect(length_counter.count).to eq(0)
      end
    end

    context 'when the channel is enabled' do
      context 'and the entry is the first' do
        subject(:length_counter) { described_class.new.tap { |counter| counter.enabled = true } }

        it 'loads 10' do
          length_counter.load(0x07)
          expect(length_counter.count).to eq(10)
        end
      end

      context 'and the entry is the second' do
        subject(:length_counter) { described_class.new.tap { |counter| counter.enabled = true } }

        it 'loads 254' do
          length_counter.load(0x08)
          expect(length_counter.count).to eq(254)
        end
      end

      context 'and the entry is the last' do
        subject(:length_counter) { described_class.new.tap { |counter| counter.enabled = true } }

        it 'loads 30' do
          length_counter.load(0xF8)
          expect(length_counter.count).to eq(30)
        end
      end
    end
  end

  describe '#clock' do
    context 'when the counter is 0' do
      subject(:length_counter) { described_class.new.tap { |counter| counter.enabled = true } }

      it 'keeps it at 0' do
        length_counter.clock
        expect(length_counter.count).to eq(0)
      end
    end

    context 'when the counter is above 0' do
      context 'but the channel halts it' do
        subject(:length_counter) do
          described_class.new.tap do |counter|
            counter.enabled = true
            counter.load(0x07)
            counter.halted = true
          end
        end

        it 'keeps its count' do
          length_counter.clock
          expect(length_counter.count).to eq(10)
        end
      end

      context 'and the channel does not halt it' do
        subject(:length_counter) do
          described_class.new.tap do |counter|
            counter.enabled = true
            counter.load(0x07)
          end
        end

        it 'decrements it' do
          length_counter.clock
          expect(length_counter.count).to eq(9)
        end
      end
    end
  end

  describe '#enabled=' do
    context 'when the channel is disabled while counting' do
      subject(:length_counter) do
        described_class.new.tap do |counter|
          counter.enabled = true
          counter.load(0x07)
        end
      end

      it 'forces the counter to 0' do
        length_counter.enabled = false
        expect(length_counter.count).to eq(0)
      end
    end

    context 'when the channel is enabled' do
      subject(:length_counter) { described_class.new }

      it 'leaves the counter at 0' do
        length_counter.enabled = true
        expect(length_counter.count).to eq(0)
      end
    end
  end

  describe '#active?' do
    context 'when the counter is 0' do
      subject(:length_counter) { described_class.new }

      it { is_expected.not_to be_active }
    end

    context 'when the counter is above 0' do
      subject(:length_counter) do
        described_class.new.tap do |counter|
          counter.enabled = true
          counter.load(0x18)
        end
      end

      it { is_expected.to be_active }
    end
  end
end
