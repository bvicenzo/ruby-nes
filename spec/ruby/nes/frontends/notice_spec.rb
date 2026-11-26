# frozen_string_literal: true

require 'ruby/nes/frontends/notice'

# A short message the window draws over the picture (plan 35, decision 9), "State 3 saved": shown for 120 frames,
# about 2 seconds, counted as the window presents them. A newer message takes the place of the older one and is shown
# for its own 120 frames.
RSpec.describe Ruby::Nes::Frontends::Notice do
  describe '#text' do
    context 'when no message was shown' do
      subject(:notice) { described_class.new }

      it 'is nil' do
        expect(notice.text).to be_nil
      end
    end

    context 'when a message was shown' do
      context 'and 119 frames have passed' do
        subject(:notice) { described_class.new }

        before do
          notice.show('State 3 saved')
          119.times { notice.tick }
        end

        it 'is the message' do
          expect(notice.text).to eq('State 3 saved')
        end
      end

      context 'and 120 frames have passed' do
        subject(:notice) { described_class.new }

        before do
          notice.show('State 3 saved')
          120.times { notice.tick }
        end

        it 'is nil' do
          expect(notice.text).to be_nil
        end
      end

      context 'and another message was shown 100 frames later' do
        subject(:notice) { described_class.new }

        before do
          notice.show('Slot 4')
          100.times { notice.tick }
          notice.show('State 4 saved')
          100.times { notice.tick }
        end

        it 'is the newer message, for its own 120 frames' do
          expect(notice.text).to eq('State 4 saved')
        end
      end
    end
  end
end
