# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The keys that drive the emulator rather than the controller (plan 18, decision 6). Built from bindings, a
      # graphics library's key code to an action of ACTIONS; several keys may share an action. Told once per frame which
      # bound keys were pressed during it: pause and the frame rate overlay toggle on each frame one of their keys is
      # pressed, reset is asked for during that frame only, quit stays asked. Frontends::Driver reads `paused?` and
      # `reset_requested?` through the frontend (plan 18, decision 5). Off the hot path: once per frame.
      class Hotkeys
        ACTIONS = %i[pause reset quit frame_rate].freeze

        def initialize(bindings)
          unknown_names = bindings.values.uniq - ACTIONS
          raise ArgumentError, "not hotkey actions: #{unknown_names.join(', ')}" if unknown_names.any?

          @bindings = bindings
          @quit = false
          @paused = false
          @reset_requested = false
          @frame_rate_shown = true
        end

        def quit? = @quit

        def paused? = @paused

        def reset_requested? = @reset_requested

        def frame_rate_shown? = @frame_rate_shown

        # The actions of the frame just presented: `{ |key_code| pressed? }`, asked about bound keys only.
        def poll
          pressed = @bindings.filter_map { |key_code, action| action if yield(key_code) }
          @quit ||= pressed.include?(:quit)
          @paused = !@paused if pressed.include?(:pause)
          @reset_requested = pressed.include?(:reset)
          @frame_rate_shown = !@frame_rate_shown if pressed.include?(:frame_rate)
        end
      end
    end
  end
end
