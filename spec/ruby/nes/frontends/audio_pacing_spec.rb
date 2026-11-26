# frozen_string_literal: true

require 'ruby/nes/frontends/raylib_audio_stream'
require 'ruby/nes/frontends/audio_pacing'

# Audio-driven pacing (plan 24): the window queues each frame's samples, and every whole chunk the stream has room for
# is submitted at once, without waiting, so a window run unpaced still feeds the speaker. After presenting, the window
# waits until the stream has room for every whole chunk still queued: the stream holds two chunks (raylib's two
# sub-buffers, refilled only once played), so waiting keeps the emulator at the pace the speaker plays. Less than a
# chunk waits for the next frame. An emulator slower than the speaker never waits: the stream runs dry between chunks
# and plays silence (plan 24, decision 2). A stream that finds no room within MAXIMUM_POLLS polls (a dead audio
# device) loses the chunks queued instead of freezing the window. The queue keeps at most MAXIMUM_CHUNKS chunks,
# dropping the oldest samples. The stream and the sleep are injected.
RSpec.describe Ruby::Nes::Frontends::AudioPacing do
  describe '#queue' do
    subject(:pacing) { described_class.new(stream:, chunk_size: 2, sleeper:) }

    let(:stream) { instance_double(Ruby::Nes::Frontends::RaylibAudioStream, submit: nil) }
    let(:sleeper) { instance_double(Proc, call: nil) }
    let(:bound) { 2 * described_class::MAXIMUM_CHUNKS }

    context 'when the stream has room' do
      before { allow(stream).to receive(:room?).and_return(true) }

      it 'submits every whole chunk at once, without sleeping', :aggregate_failures do
        pacing.queue([1, 2, 3, 4, 5])

        expect(stream).to have_received(:submit).with([1, 2]).ordered
        expect(stream).to have_received(:submit).with([3, 4]).ordered
        expect(stream).to have_received(:submit).twice
        expect(sleeper).not_to have_received(:call)
      end
    end

    context 'when the stream has no room' do
      before { allow(stream).to receive(:room?).and_return(false) }

      context 'and the samples would pass its bound' do
        it 'drops the oldest samples', :aggregate_failures do
          pacing.queue(Array.new(bound) { it })
          pacing.queue([100, 101])
          allow(stream).to receive(:room?).and_return(true)
          pacing.wait

          expect(stream).not_to have_received(:submit).with([0, 1])
          expect(stream).to have_received(:submit).with([100, 101])
        end
      end

      context 'and they stay within it' do
        it 'keeps them all for the wait', :aggregate_failures do
          pacing.queue(Array.new(bound) { it })
          allow(stream).to receive(:room?).and_return(true)
          pacing.wait

          expect(stream).to have_received(:submit).exactly(described_class::MAXIMUM_CHUNKS).times
          expect(stream).to have_received(:submit).with([0, 1])
        end
      end
    end
  end

  describe '#wait' do
    subject(:pacing) { described_class.new(stream:, chunk_size: 2, sleeper:) }

    let(:stream) { instance_double(Ruby::Nes::Frontends::RaylibAudioStream, submit: nil) }
    let(:sleeper) { instance_double(Proc, call: nil) }

    context 'when less than a chunk is queued' do
      before { allow(stream).to receive(:room?).and_return(true) }

      it 'submits nothing and does not sleep', :aggregate_failures do
        pacing.queue([100])
        pacing.wait

        expect(stream).not_to have_received(:submit)
        expect(sleeper).not_to have_received(:call)
      end
    end

    context 'when a whole chunk is still queued' do
      context 'but the stream finds no room within the poll limit' do
        before { allow(stream).to receive(:room?).and_return(false) }

        it 'drops the chunks queued without submitting them', :aggregate_failures do
          pacing.queue([1, 2, 3, 4])
          pacing.wait
          allow(stream).to receive(:room?).and_return(true)
          pacing.wait

          expect(sleeper).to have_received(:call).exactly(described_class::MAXIMUM_POLLS).times
          expect(stream).not_to have_received(:submit)
        end
      end

      context 'and the stream finds room within the poll limit' do
        before { allow(stream).to receive(:room?).and_return(false, false, false, true) }

        it 'sleeps a poll interval until it has room, then submits every whole chunk in order', :aggregate_failures do
          submitted = []
          allow(stream).to receive(:submit) { |chunk| submitted << chunk }
          pacing.queue([1, 2, 3, 4, 5])
          pacing.wait

          expect(sleeper).to have_received(:call).with(described_class::POLL_SECONDS).twice
          expect(submitted).to eq([[1, 2], [3, 4]])
        end
      end
    end
  end

  describe '#queue_silence' do
    subject(:pacing) { described_class.new(stream:, chunk_size: 2, sleeper:) }

    let(:stream) { instance_double(Ruby::Nes::Frontends::RaylibAudioStream, submit: nil, room?: true) }
    let(:sleeper) { instance_double(Proc, call: nil) }

    it 'queues a chunk of zeros' do
      pacing.queue_silence

      expect(stream).to have_received(:submit).once.with([0, 0])
    end
  end

  # After a save state is loaded, the sound queued is of the moment left behind (plan 35, decision 8).
  describe '#clear' do
    subject(:pacing) { described_class.new(stream:, chunk_size: 2, sleeper:) }

    let(:stream) { instance_double(Ruby::Nes::Frontends::RaylibAudioStream, submit: nil) }
    let(:sleeper) { instance_double(Proc, call: nil) }

    before { allow(stream).to receive(:room?).and_return(false) }

    it 'drops the samples queued, so none is submitted' do
      pacing.queue([1, 2, 3, 4, 5])
      pacing.clear
      allow(stream).to receive(:room?).and_return(true)
      pacing.wait

      expect(stream).not_to have_received(:submit)
    end
  end
end
