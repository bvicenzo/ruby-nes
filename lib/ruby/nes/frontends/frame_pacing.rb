# frozen_string_literal: true

require_relative 'monotonic_clock'

module Ruby
  module Nes
    module Frontends
      # Keeps a windowed frontend at the NTSC frame rate by waiting after each frame it presents (plan 18). Deadlines
      # are one period apart from the moment the pacing starts, never from the moment a sleep ends, so what a sleep
      # oversleeps does not accumulate into drift. A frame late by less than a period keeps the schedule (the next
      # frame gets less time); a frame late by a period or more restarts it from now, so a slow emulator runs as fast
      # as it can, without running frames back to back to catch up. Off the hot path: once per frame.
      class FramePacing
        # "Frame rate (vertical scan rate)", NTSC: "60.0988 Hz" (https://www.nesdev.org/wiki/Cycle_reference_chart).
        FRAMES_PER_SECOND = 60.0988
        PERIOD = 1 / FRAMES_PER_SECOND

        # `clock` returns monotonic seconds, `sleeper` sleeps the seconds it is given. The first frame's deadline is one
        # period after the pacing is built.
        def initialize(clock: MonotonicClock, sleeper: Kernel.method(:sleep))
          @clock = clock
          @sleeper = sleeper
          @deadline = clock.call + PERIOD
        end

        # Sleeps until the frame's deadline, if it is still ahead, and sets the next one.
        def wait
          now = @clock.call
          @sleeper.call(@deadline - now) if now < @deadline
          @deadline = a_period_late?(now) ? now + PERIOD : @deadline + PERIOD
        end

        private

        def a_period_late?(now) = now >= @deadline + PERIOD
      end
    end
  end
end
