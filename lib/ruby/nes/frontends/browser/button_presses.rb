# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # The buttons the browser takes as pressed in a frame (plan 37, decision 6), from those held on controller 1:
        # a button is pressed on the frame it starts being held. A direction held on is pressed again after
        # REPEAT_DELAY frames and every REPEAT_INTERVAL frames from then on, so a held direction scrolls the list; the
        # other buttons never repeat, so A or Start held as a game ends starts nothing. Each button is timed on its own.
        # Off the hot path: once per menu frame.
        class ButtonPresses
          # About a third of a second, then 10 rows a second, at 60.0988 frames per second
          # (https://www.nesdev.org/wiki/Cycle_reference_chart).
          REPEAT_DELAY = 20
          REPEAT_INTERVAL = 6
          FIRST_FRAME = 1
          DIRECTIONS = Input::Controller::BUTTONS.values_at(:up, :down, :left, :right).freeze

          def initialize
            @frames_held = Input::Controller::BUTTONS.values.to_h { [it, 0] }
          end

          # The mask of the buttons pressed in this frame, from `held`, the mask of the buttons held in it (both in
          # Input::Controller::BUTTONS's bits).
          def presses(held)
            @frames_held.each_key.reduce(0) do |pressed, button|
              frames = @frames_held[button] = held.anybits?(button) ? @frames_held[button] + 1 : 0
              pressed?(button, frames) ? Bits.set_flag(pressed, button) : pressed
            end
          end

          private

          # Never for a button not held (0 frames).
          def pressed?(button, frames)
            return true if frames == FIRST_FRAME
            return false unless DIRECTIONS.include?(button)

            frames_repeating = frames - FIRST_FRAME - REPEAT_DELAY
            !frames_repeating.negative? && (frames_repeating % REPEAT_INTERVAL).zero?
          end
        end
      end
    end
  end
end
