# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The pad's way into the menus (plan 38, decision 3): gamepad buttons held together on the first gamepad, L and R
      # in the window (raylib's LEFT_TRIGGER_1 and RIGHT_TRIGGER_1; NES games never see them). Polled once per frame,
      # it is pressed on the poll where the last of them becomes held, and not again until one is let go. A gamepad is
      # read only while the library says it is available, so an absent one holds nothing (plan 36, decision 6). Off the
      # hot path: once per frame.
      class MenuCombination
        GAMEPAD = 0

        # `buttons` are the graphics library's codes of the gamepad buttons held together.
        def initialize(buttons:)
          @buttons = buttons
          @held = false
          restart
        end

        # Whether the buttons became held together at the last poll.
        def pressed? = @pressed

        # Starts over as a menu closes or a screen changes (plan 38): no longer pressed, and buttons still held are no
        # new press, so the L + R that closed a menu does not open it again.
        def restart
          @pressed = false
        end

        # Reads the gamepad from `input` (Frontends::RaylibInput's interface: `gamepad_available?(gamepad)`,
        # `gamepad_button_down?(gamepad, code)`).
        def poll(input)
          held = input.gamepad_available?(GAMEPAD) && @buttons.all? { input.gamepad_button_down?(GAMEPAD, it) }
          @pressed = held && !@held
          @held = held
        end
      end
    end
  end
end
