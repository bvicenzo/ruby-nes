# frozen_string_literal: true

# The triangle's 32-step sequencer (https://www.nesdev.org/wiki/APU_Triangle): it outputs 15, 14, 13, …, 1, 0, then 0,
# 1, 2, …, 14, 15, and repeats. After reset the "Triangle phase" is "0 (output = 15)"
# (https://www.nesdev.org/wiki/CPU_power_up_state).
RSpec.describe Ruby::Nes::Apu::TriangleSequencer do
  describe '#output' do
    context 'when the sequencer has not stepped' do
      subject(:sequencer) { described_class.new }

      it 'is 15' do
        expect(sequencer.output).to eq(15)
      end
    end

    context 'when it stepped once' do
      subject(:sequencer) { described_class.new.tap(&:step) }

      it 'is 14' do
        expect(sequencer.output).to eq(14)
      end
    end

    context 'when it stepped 15 times' do
      subject(:sequencer) { described_class.new.tap { |sequencer| 15.times { sequencer.step } } }

      it 'is 0' do
        expect(sequencer.output).to eq(0)
      end
    end

    context 'when it stepped 16 times' do
      subject(:sequencer) { described_class.new.tap { |sequencer| 16.times { sequencer.step } } }

      it 'is 0' do
        expect(sequencer.output).to eq(0)
      end
    end

    context 'when it stepped 17 times' do
      subject(:sequencer) { described_class.new.tap { |sequencer| 17.times { sequencer.step } } }

      it 'is 1' do
        expect(sequencer.output).to eq(1)
      end
    end

    context 'when it stepped 31 times' do
      subject(:sequencer) { described_class.new.tap { |sequencer| 31.times { sequencer.step } } }

      it 'is 15' do
        expect(sequencer.output).to eq(15)
      end
    end

    context 'when it stepped 32 times' do
      subject(:sequencer) { described_class.new.tap { |sequencer| 32.times { sequencer.step } } }

      it 'is 15, the first step again' do
        expect(sequencer.output).to eq(15)
      end
    end

    context 'when it stepped 33 times' do
      subject(:sequencer) { described_class.new.tap { |sequencer| 33.times { sequencer.step } } }

      it 'is 14, the second step again' do
        expect(sequencer.output).to eq(14)
      end
    end
  end

  describe '#reset' do
    context 'when the sequencer stepped into the sequence' do
      subject(:sequencer) { described_class.new.tap { |sequencer| 20.times { sequencer.step } } }

      it 'goes back to the first step' do
        sequencer.reset
        expect(sequencer.output).to eq(15)
      end
    end
  end
end
