# frozen_string_literal: true

require 'ruby/nes/frontends/frame_rate'

# The frame rate a windowed frontend shows (plan 18): the frames it presented over each completed window of at least
# a second, divided by the seconds the window took. A window closes on the first frame presented a second or more
# after it opened, and the next one opens there; the frames of a window still open never mix into the rate shown. The
# clock is injected: here one that reads the given moments in turn, in seconds from the start.
RSpec.describe Ruby::Nes::Frontends::FrameRate do
  describe '#per_second' do
    subject(:frame_rate) { described_class.new(clock:) }

    let(:clock) { instance_double(Proc) }

    before do
      allow(clock).to receive(:call).and_return(0.0, *frame_ends)
      frame_ends.size.times { frame_rate.tick }
    end

    context 'when less than a second has passed since the start' do
      let(:frame_ends) { [0.25, 0.5, 0.75, 0.999] }

      it 'is nil' do
        expect(frame_rate.per_second).to be_nil
      end
    end

    context 'when a second has passed' do
      context 'and a frame ended exactly on it' do
        let(:frame_ends) { [0.25, 0.5, 0.75, 1.0] }

        it 'is the frames presented in that second' do
          expect(frame_rate.per_second).to eq(4.0)
        end
      end

      context 'and the first frame past it ended later' do
        let(:frame_ends) { [0.5, 0.75, 1.5] }

        it 'is the frames divided by the seconds they took' do
          expect(frame_rate.per_second).to eq(2.0)
        end
      end
    end

    context 'when frames follow a completed second' do
      context 'but less than another second' do
        let(:frame_ends) { [0.5, 1.0, 1.1, 1.2, 1.3, 1.4] }

        it 'is still the rate of the completed second' do
          expect(frame_rate.per_second).to eq(2.0)
        end
      end

      context 'and another second' do
        let(:frame_ends) { [0.5, 1.0, 1.25, 1.5, 1.75, 2.0] }

        it 'is the rate of the newest second' do
          expect(frame_rate.per_second).to eq(4.0)
        end
      end
    end
  end

  describe '#to_s' do
    subject(:frame_rate) { described_class.new(clock:) }

    let(:clock) { instance_double(Proc) }

    before do
      allow(clock).to receive(:call).and_return(0.0, *frame_ends)
      frame_ends.size.times { frame_rate.tick }
    end

    context 'when no second has completed' do
      let(:frame_ends) { [0.5] }

      it 'shows no rate' do
        expect(frame_rate.to_s).to eq('-- fps')
      end
    end

    context 'when a second has completed' do
      let(:frame_ends) { [0.3, 0.6, 1.5] }

      it 'shows the rate with one decimal' do
        expect(frame_rate.to_s).to eq('2.0 fps')
      end
    end
  end
end
