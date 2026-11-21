# frozen_string_literal: true

# The pulse channel's 8-step sequencer (https://www.nesdev.org/wiki/APU_Pulse). Its duty (bits 7-6 of the first
# register) picks one of four waveforms, 0 1 0 0 0 0 0 0 (12.5%), 0 1 1 0 0 0 0 0 (25%), 0 1 1 1 1 0 0 0 (50%) and
# 1 0 0 1 1 1 1 1 (25% negated); the hardware reads its lookup table "in the order 0, 7, 6, 5, 4, 3, 2, 1", which gives
# those waveforms from the first step. A write to the fourth register "resets the sequencer index ... to the first
# value". It starts on the first step of duty 0.
RSpec.describe Ruby::Nes::Apu::DutySequencer do
  describe '#output' do
    context 'when the duty is 0' do
      subject(:sequencer) { described_class.new }

      it 'plays 0 1 0 0 0 0 0 0' do
        expect(sequencer).to play_waveform([0, 1, 0, 0, 0, 0, 0, 0])
      end
    end

    context 'when the duty is 1' do
      subject(:sequencer) { described_class.new.tap { |duty_sequencer| duty_sequencer.duty = 1 } }

      it 'plays 0 1 1 0 0 0 0 0' do
        expect(sequencer).to play_waveform([0, 1, 1, 0, 0, 0, 0, 0])
      end
    end

    context 'when the duty is 2' do
      subject(:sequencer) { described_class.new.tap { |duty_sequencer| duty_sequencer.duty = 2 } }

      it 'plays 0 1 1 1 1 0 0 0' do
        expect(sequencer).to play_waveform([0, 1, 1, 1, 1, 0, 0, 0])
      end
    end

    context 'when the duty is 3' do
      subject(:sequencer) { described_class.new.tap { |duty_sequencer| duty_sequencer.duty = 3 } }

      it 'plays 1 0 0 1 1 1 1 1' do
        expect(sequencer).to play_waveform([1, 0, 0, 1, 1, 1, 1, 1])
      end
    end
  end

  describe '#restart' do
    context 'when the sequencer is past its first step' do
      subject(:sequencer) do
        described_class.new.tap do |duty_sequencer|
          duty_sequencer.duty = 2
          3.times { duty_sequencer.step }
        end
      end

      it 'plays the waveform from its first step again' do
        sequencer.restart
        expect(sequencer).to play_waveform([0, 1, 1, 1, 1, 0, 0, 0])
      end
    end
  end
end
