# frozen_string_literal: true

require_relative 'controls'
require_relative 'stick_directions'

module Ruby
  module Nes
    module Frontends
      # The window's gamepads as standard controllers (plan 36), one bound layout for all of them: a pad's buttons bound
      # through Frontends::Controls, and its left stick as directions (Frontends::StickDirections). Opposite directions
      # are left for Frontends::Players to cancel per port. Off the hot path: once per frame.
      class Gamepad
        # `controls` binds the graphics library's gamepad button codes to controller buttons.
        def initialize(controls)
          @controls = controls
        end

        # The controller mask of the library's `gamepad` (its number), read from `input` (Frontends::RaylibInput's
        # interface: `gamepad_button_down?(gamepad, code)`, `left_stick(gamepad)`).
        def buttons(gamepad, input)
          held = @controls.buttons { input.gamepad_button_down?(gamepad, it) }
          Bits.set_flag(held, StickDirections.buttons(*input.left_stick(gamepad)))
        end
      end
    end
  end
end
