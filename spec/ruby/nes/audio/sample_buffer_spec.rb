# frozen_string_literal: true

# The samples of a frame, kept in a buffer allocated once (no allocation per sample, docs/architecture.md, Hot paths)
# until the frontend drains them. A full buffer drops the new samples: nobody drained it, so they have nowhere to go.
RSpec.describe Ruby::Nes::Audio::SampleBuffer do
  describe '#drain' do
    subject(:buffer) { described_class.new(capacity: 4) }

    context 'when nothing was pushed' do
      it 'returns no samples' do
        expect(buffer.drain).to eq([])
      end
    end

    context 'when samples were pushed' do
      context 'but more than its capacity' do
        it 'returns the first ones up to its capacity, dropping the later ones' do
          [10, 20, 30, 40, 50].each { buffer.push(it) }

          expect(buffer.drain).to eq([10, 20, 30, 40])
        end
      end

      context 'and exactly its capacity' do
        it 'returns them all, in order' do
          [10, 20, 30, 40].each { buffer.push(it) }

          expect(buffer.drain).to eq([10, 20, 30, 40])
        end
      end

      context 'and fewer than its capacity' do
        it 'returns them in order' do
          [10, -20].each { buffer.push(it) }

          expect(buffer.drain).to eq([10, -20])
        end
      end
    end

    context 'when it was drained before' do
      it 'returns only the samples pushed since' do
        [10, 20, 30, 40].each { buffer.push(it) }
        buffer.drain
        [50, 60].each { buffer.push(it) }

        expect(buffer.drain).to eq([50, 60])
      end
    end

    context 'when samples are pushed after a drain' do
      it 'leaves the drained samples unchanged' do
        [10, 20].each { buffer.push(it) }
        drained = buffer.drain
        [30, 40].each { buffer.push(it) }

        expect(drained).to eq([10, 20])
      end
    end
  end
end
