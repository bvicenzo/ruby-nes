# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # The pause menu over a game in the window (plan 38), opened by Frontends::Driver when the window asks for the
      # menu. The menu (Frontends::Pause::Menu) opens over the frame on screen and runs in the window
      # (CommandLine::MenuLoop) until a choice is made, which is then done: a slot chosen to save or load becomes the
      # current one and the game's Saves::StateSlots save or load there, saying so; RESET resets the console; these and
      # RESUME resume the window. BACK TO THE LIST, offered only for a game started from the ROM list, ends the game's
      # screen, and QUIT the session. A window that stops running in the menu has nothing done. Off the hot path.
      class Pause
        ENTRIES = Frontends::Pause::Menu::LABELS.keys.freeze
        STATE_ACTIONS = Frontends::Pause::Menu::STATE_ACTIONS

        # The pause menu of `console`'s game, whose save state slots are `slots` (Saves::StateSlots); `back_to_list`
        # when it was started from the ROM list.
        def initialize(console:, slots:, back_to_list:)
          @console = console
          @slots = slots
          @entries = back_to_list ? ENTRIES : ENTRIES - [:back_to_list]
        end

        # Runs the menu in `frontend` (Frontends::Base) and does what is chosen.
        def open(frontend)
          menu = Frontends::Pause::Menu.new(entries: @entries, background: @console.ppu.frame_buffer, slots: @slots)
          choice = MenuLoop.run(frontend:, menu:)
          perform(choice, frontend) if choice
        end

        private

        def perform(choice, frontend)
          case choice.action
          when :back_to_list then return frontend.leave
          when :quit then return frontend.quit
          when :reset then @console.reset
          when *STATE_ACTIONS then perform_state_action(choice, frontend)
          end
          frontend.resume
        end

        def perform_state_action(choice, frontend)
          @slots.pick(choice.slot)
          @slots.perform(choice.action, frontend)
        end
      end
    end
  end
end
