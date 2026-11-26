# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # A short message a windowed frontend draws over the picture (plan 35, decision 9), "State 3 saved": shown for
      # FRAMES_SHOWN frames, counted by `tick` as the window presents them. A newer message takes the older one's place
      # and its own FRAMES_SHOWN frames. Off the hot path: once per frame.
      class Notice
        # About 2 seconds at 60.0988 frames per second.
        FRAMES_SHOWN = 120

        def initialize
          @message = nil
          @frames_left = 0
        end

        def show(message)
          @message = message
          @frames_left = FRAMES_SHOWN
        end

        # Counts a frame presented.
        def tick
          @frames_left -= 1
        end

        # The message to draw, or nil once its frames have passed.
        def text = (@message if @frames_left.positive?)
      end
    end
  end
end
