# frozen_string_literal: true

require_relative 'controls'
require_relative 'gamepad'
require_relative 'opposite_directions'

module Ruby
  module Nes
    module Frontends
      # The window's inputs as the console's two controllers (plan 36, decision 2): port 1 is the keyboard and raylib's
      # gamepad 0, their buttons combined, so one person with one pad plays as player 1 with the keyboard still at hand;
      # port 2 is gamepad 1. Ports follow raylib's numbers: with two pads in, pulling out the first leaves the second on
      # port 2. A gamepad is read only while the library says it is available, asked every frame,
      # so pulling one out releases its buttons and plugging it back resumes (decision 6). Each port's opposite
      # directions cancel once combined (Frontends::OppositeDirections, plan 18, decision 3). Off the hot path: once per
      # frame.
      class Players
        FIRST_GAMEPAD = 0
        SECOND_GAMEPAD = 1

        # `keyboard` binds key codes to controller buttons (Frontends::Controls); `gamepad` reads any pad
        # (Frontends::Gamepad).
        def initialize(keyboard:, gamepad:)
          @keyboard = keyboard
          @gamepad = gamepad
        end

        # Both controllers' masks, `[first, second]` (Frontends::Base#button_states), read from `input`
        # (Frontends::RaylibInput's interface: `key_down?(code)`, `gamepad_available?(gamepad)`, and the pad's own).
        def button_states(input)
          keys = @keyboard.buttons { input.key_down?(it) }
          first = Bits.set_flag(keys, gamepad_buttons(FIRST_GAMEPAD, input))
          [OppositeDirections.filter(first), OppositeDirections.filter(gamepad_buttons(SECOND_GAMEPAD, input))]
        end

        private

        def gamepad_buttons(gamepad, input)
          return 0 unless input.gamepad_available?(gamepad)

          @gamepad.buttons(gamepad, input)
        end
      end
    end
  end
end
