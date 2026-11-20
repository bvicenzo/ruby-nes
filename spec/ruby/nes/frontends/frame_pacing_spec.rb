# frozen_string_literal: true

require 'ruby/nes/frontends/frame_pacing'

# The windowed frontend waits after each frame it presents, so the emulator runs at the NTSC frame rate, 60.0988
# frames per second (https://www.nesdev.org/wiki/Cycle_reference_chart). Deadlines follow one another a period apart
# from the moment the pacing starts, so the time a sleep oversleeps never accumulates; a frame late by a period or
# more restarts the schedule instead of running the next frames back to back. The clock and the sleep are injected:
# here a clock that reads the given moments in turn, in seconds.
RSpec.describe Ruby::Nes::Frontends::FramePacing do
  describe '#wait' do
    subject(:pacing) { described_class.new(clock:, sleeper:) }

    let(:clock) { instance_double(Proc) }
    let(:sleeper) { instance_double(Proc, call: nil) }
    let(:start) { 100.0 }
    let(:period) { described_class::PERIOD }
    let(:tolerance) { 1e-9 }

    before { allow(clock).to receive(:call).and_return(start, frame_end, next_frame_end) }

    context 'when the frame ends before its deadline' do
      let(:frame_end) { start + 0.010 }
      let(:next_frame_end) { start + period + 0.005 }

      it 'sleeps the time left until the deadline' do
        pacing.wait

        expect(sleeper).to have_received(:call).with(a_value_within(tolerance).of(period - 0.010))
      end

      it 'sets the next deadline one period after this one' do
        2.times { pacing.wait }

        expect(sleeper).to have_received(:call).with(a_value_within(tolerance).of(period - 0.005))
      end
    end

    context 'when the frame ends exactly at its deadline' do
      let(:frame_end) { start + period }
      let(:next_frame_end) { start + period + 0.005 }

      it 'does not sleep' do
        pacing.wait

        expect(sleeper).not_to have_received(:call)
      end

      it 'sets the next deadline one period after this one' do
        2.times { pacing.wait }

        expect(sleeper).to have_received(:call).once.with(a_value_within(tolerance).of(period - 0.005))
      end
    end

    context 'when the frame ends past its deadline' do
      context 'but less than a period late' do
        let(:frame_end) { start + period + 0.005 }
        let(:next_frame_end) { start + period + 0.010 }

        it 'does not sleep' do
          pacing.wait

          expect(sleeper).not_to have_received(:call)
        end

        it 'sets the next deadline one period after the missed one' do
          2.times { pacing.wait }

          expect(sleeper).to have_received(:call).once.with(a_value_within(tolerance).of(period - 0.010))
        end
      end

      context 'and exactly a period late' do
        let(:frame_end) { start + period + period }
        let(:next_frame_end) { frame_end + 0.005 }

        it 'does not sleep' do
          pacing.wait

          expect(sleeper).not_to have_received(:call)
        end

        it 'restarts the schedule one period from now' do
          2.times { pacing.wait }

          expect(sleeper).to have_received(:call).once.with(a_value_within(tolerance).of(period - 0.005))
        end
      end

      context 'and many periods late' do
        let(:frame_end) { start + 0.5 }
        let(:next_frame_end) { start + 0.505 }

        it 'does not sleep' do
          pacing.wait

          expect(sleeper).not_to have_received(:call)
        end

        it 'restarts the schedule one period from now' do
          2.times { pacing.wait }

          expect(sleeper).to have_received(:call).once.with(a_value_within(tolerance).of(period - 0.005))
        end
      end
    end
  end
end
