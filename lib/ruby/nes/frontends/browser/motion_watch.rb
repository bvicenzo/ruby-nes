# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # Whether a game left alone from power-up has started moving (plan 37, decision 2): the different pictures shown
        # are counted second by second, and the first second showing PICTURES_TO_MOVE of them marks the moving picture
        # (a demo, an animated title). A still title whose text blinks, or that cycles through a few pictures, never
        # reaches it, however often they change: counting changes instead found Super Pitfall moving in its first
        # second, 20 s before its demo. On the six local games the picture moves after 2 to 22 s (plan 37, Context).
        # Off the hot path: once per preview frame, a picture kept as its frame buffer's hash (about 0.4 ms).
        class MotionWatch
          # A second at 60.0988 frames per second, rounded (https://www.nesdev.org/wiki/Cycle_reference_chart).
          FRAMES_PER_SECOND = 60
          PICTURES_TO_MOVE = 30

          def initialize
            @frames = 0
            @pictures = {}
            @moving = false
          end

          def moving? = @moving

          # Counts the frame `frame_buffer` (docs/architecture.md, Frame buffer contract) just presented.
          def watch(frame_buffer)
            @pictures[frame_buffer.hash] = true
            @frames += 1
            return unless (@frames % FRAMES_PER_SECOND).zero?

            @moving ||= @pictures.size >= PICTURES_TO_MOVE
            @pictures.clear
          end
        end
      end
    end
  end
end
