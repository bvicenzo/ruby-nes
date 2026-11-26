# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # A menu over a paused screen in the window (plan 38): the pause menu over a game (CommandLine::Pause), the ROM
      # list's menu (CommandLine::Browser). Each frame the window gets a frame of silence, unless paused, so the audio
      # keeps pacing it (plan 37, decision 7), and the menu's picture; then the menu's key or buttons, read as the frame
      # was presented (Frontends::Base#menu_requested?), close it as Pause::Choice::RESUME, or else the menu
      # (Frontends::Pause::Menu) is told controller 1's presses (Frontends::Screens::ButtonPresses) and its first choice
      # ends the loop. A button held as the menu opens is no press until let go. Off the hot path: once per menu frame.
      module MenuLoop
        # The Frontends::Pause::Choice made in `menu`, shown in `frontend`, or nil when the window stops running.
        def self.run(frontend:, menu:)
          button_presses = Frontends::Screens::ButtonPresses.new.tap { it.presses(frontend.button_states.first) }
          while frontend.running?
            frontend.queue_silence unless frontend.paused?
            frontend.present(menu.picture)
            return Frontends::Pause::Choice::RESUME if frontend.menu_requested?

            choice = menu.tick(button_presses.presses(frontend.button_states.first))
            return choice if choice
          end
        end
      end
    end
  end
end
