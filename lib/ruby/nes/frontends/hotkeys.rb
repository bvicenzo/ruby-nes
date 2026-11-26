# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The keys that drive the emulator rather than the controller (plan 18, decision 6). Built from bindings, a
      # graphics library's key code to an action of ACTIONS; several keys may share an action. Told once per frame which
      # bound keys were pressed during it: pause and the frame rate overlay toggle on each frame one of their keys is
      # pressed, reset, the menu (plan 38, decision 2) and a save state action (plan 35, decision 3) are asked for
      # during that frame only, quit stays asked. Frontends::Driver reads `paused?`, `reset_requested?`,
      # `menu_requested?` and `state_action` through the frontend (plan 18, decision 5). Off the hot path: once per
      # frame.
      class Hotkeys
        # Saves::StateSlots::ACTIONS, in the order that picks one when several keys are pressed together.
        STATE_ACTIONS = %i[save_state load_state previous_slot next_slot].freeze
        ACTIONS = [:pause, :reset, :quit, :menu, :frame_rate, *STATE_ACTIONS].freeze

        def initialize(bindings)
          unknown_names = bindings.values.uniq - ACTIONS
          raise ArgumentError, "not hotkey actions: #{unknown_names.join(', ')}" if unknown_names.any?

          @bindings = bindings
          @frame_rate_shown = true
          restart
        end

        # Starts over, as for another screen of the ROM browser (plan 37, decision 7): not quitting, not paused, nothing
        # asked. The overlay stays as the player left it.
        def restart
          @quit = false
          @paused = false
          @reset_requested = false
          @menu_requested = false
          @state_action = nil
        end

        def quit? = @quit

        def paused? = @paused

        def reset_requested? = @reset_requested

        # Whether a menu key was pressed during the last poll: the pause menu in a game, the list's menu in the ROM
        # browser, closing a menu that is open (plan 38, decision 2).
        def menu_requested? = @menu_requested

        def frame_rate_shown? = @frame_rate_shown

        # The save state action asked for during the last poll, or nil.
        attr_reader :state_action

        # The actions of the frame just presented: `{ |key_code| pressed? }`, asked about bound keys only.
        def poll
          pressed = @bindings.filter_map { |key_code, action| action if yield(key_code) }
          @quit ||= pressed.include?(:quit)
          @paused = !@paused if pressed.include?(:pause)
          @reset_requested = pressed.include?(:reset)
          @menu_requested = pressed.include?(:menu)
          @frame_rate_shown = !@frame_rate_shown if pressed.include?(:frame_rate)
          @state_action = STATE_ACTIONS.find { pressed.include?(it) }
        end
      end
    end
  end
end
