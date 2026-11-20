# frozen_string_literal: true

require_relative 'key_config'

module Ruby
  module Nes
    module Frontends
      # The keys of a Frontends::KeyConfig as the graphics library's key codes (plan 18, decision 7): `controller` for
      # Frontends::Keyboard, `hotkeys` for Frontends::Hotkeys. A key drives one action only: a key code holds a single
      # button in Keyboard's bindings, so a second action would silently take its place. Off the hot path: built once.
      class KeyBindings
        # Key codes to controller button names, and key codes to hotkey actions.
        attr_reader :controller, :hotkeys

        # `keys` maps each action to the names of its keys; `key_codes` maps the library's key names to its codes.
        # Raises KeyConfig::InvalidConfig when a name is not a key or a key is bound twice.
        def initialize(keys, key_codes:)
          actions = keys.each_with_object({}) do |(action, names), bound|
            names.each { bind(bound, key_code(key_codes, action, it), it, action) }
          end
          button_bindings, hotkey_bindings = actions.partition { |_code, action| button?(action) }
          @controller = button_bindings.to_h
          @hotkeys = hotkey_bindings.to_h
        end

        private

        def button?(action) = Input::Controller::BUTTONS.has_key?(action)

        def key_code(key_codes, action, name)
          key_codes.fetch(name) { raise KeyConfig::InvalidConfig, "#{name.inspect} (#{action}) is not a key name" }
        end

        def bind(bound, code, name, action)
          other_action = bound[code]
          raise KeyConfig::InvalidConfig, "#{name.inspect} is bound to #{other_action} and #{action}" if other_action

          bound[code] = action
        end
      end
    end
  end
end
