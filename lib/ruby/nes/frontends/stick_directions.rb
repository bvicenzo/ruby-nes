# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # A gamepad's analog stick as the D-pad (plan 36, decision 5), for pads with one: each axis, from -1.0 to 1.0
      # with left and up negative (raylib's GetGamepadAxisMovement), holds a direction only past DEAD_ZONE, so a stick
      # resting slightly off centre holds nothing. Opposite directions cannot come from one stick. Off the hot path:
      # once per frame.
      module StickDirections
        DEAD_ZONE = 0.5

        # The controller mask (Input::Controller::BUTTONS) of the stick's two axes: Left or Right, and Up or Down.
        def self.buttons(horizontal, vertical)
          Bits.set_flag(
            direction(horizontal, negative: :left, positive: :right),
            direction(vertical, negative: :up, positive: :down)
          )
        end

        # The mask of one axis: the `negative` button past the dead zone below the centre, the `positive` one above it,
        # nothing within it.
        def self.direction(axis, negative:, positive:)
          return Input::Controller::BUTTONS[negative] if axis < -DEAD_ZONE
          return Input::Controller::BUTTONS[positive] if axis > DEAD_ZONE

          0
        end
      end
    end
  end
end
