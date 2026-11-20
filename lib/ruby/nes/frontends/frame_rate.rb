# frozen_string_literal: true

require_relative 'monotonic_clock'

module Ruby
  module Nes
    module Frontends
      # The frame rate a windowed frontend measures and shows (plan 18): the frames presented over the last completed
      # window of at least a second, divided by the seconds that window took. A window closes on the first frame
      # presented a second or more after it opened, and the next window opens there. Off the hot path: once per frame.
      class FrameRate
        WINDOW_SECONDS = 1.0
        NO_RATE = '-- fps'

        # Frames per second over the last completed window; nil until the first one completes.
        attr_reader :per_second

        # `clock` returns monotonic seconds; the first window opens when the frame rate is built.
        def initialize(clock: MonotonicClock)
          @clock = clock
          @window_start = clock.call
          @frames = 0
          @per_second = nil
        end

        # Counts a frame presented.
        def tick
          now = @clock.call
          @frames += 1
          elapsed = now - @window_start
          return if elapsed < WINDOW_SECONDS

          @per_second = @frames / elapsed
          @window_start = now
          @frames = 0
        end

        # The rate as the overlay shows it: "60.1 fps".
        def to_s
          return NO_RATE unless @per_second

          format('%.1f fps', @per_second)
        end
      end
    end
  end
end
