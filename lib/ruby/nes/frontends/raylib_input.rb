# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The controllers' input on raylib (https://www.raylib.com/cheatsheet/cheatsheet.html), as Frontends::Players and
      # Frontends::Gamepad ask for it (plan 36): an adapter with no decision of its own. Gamepads are raylib's numbers,
      # 0 to 3. raylib polls its input when a frame's drawing ends and follows gamepads being plugged in and out itself.
      # Loads without the gem, which only its calls need, so the specs of its users can name it. The hotkeys read the
      # keyboard on their own (Frontends::Raylib). Off the hot path: once per frame.
      module RaylibInput
        def self.key_down?(code) = ::Raylib.IsKeyDown(code)

        def self.gamepad_available?(gamepad) = ::Raylib.IsGamepadAvailable(gamepad)

        def self.gamepad_button_down?(gamepad, code) = ::Raylib.IsGamepadButtonDown(gamepad, code)

        # The left stick's axes, `[horizontal, vertical]`, each from -1.0 to 1.0, left and up negative.
        def self.left_stick(gamepad)
          [
            ::Raylib.GetGamepadAxisMovement(gamepad, ::Raylib::GAMEPAD_AXIS_LEFT_X),
            ::Raylib.GetGamepadAxisMovement(gamepad, ::Raylib::GAMEPAD_AXIS_LEFT_Y)
          ]
        end
      end
    end
  end
end
