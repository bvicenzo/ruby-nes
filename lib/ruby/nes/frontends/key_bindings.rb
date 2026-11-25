# frozen_string_literal: true

require_relative 'key_config'

module Ruby
  module Nes
    module Frontends
      # The inputs of a Frontends::KeyConfig section as the graphics library's codes (plan 18, decision 7), its keys or
      # its gamepad buttons (plan 36): `controller` for Frontends::Controls, `hotkeys` for Frontends::Hotkeys. An input
      # drives one action only: a code holds a single button in Controls' bindings, so a second action would silently
      # take its place. Off the hot path: built once.
      class KeyBindings
        # Codes to controller button names, and codes to hotkey actions.
        attr_reader :controller, :hotkeys

        # `inputs` maps each action to the names of its inputs; `codes` maps the library's names to its codes, and
        # `kind` names the inputs in the errors (`key`, `gamepad button`). Raises KeyConfig::InvalidConfig when a name
        # is not the library's or an input is bound twice.
        def initialize(inputs, codes:, kind:)
          @kind = kind
          actions = inputs.each_with_object({}) do |(action, names), bound|
            names.each { bind(bound, code(codes, action, it), it, action) }
          end
          button_bindings, hotkey_bindings = actions.partition { |_code, action| button?(action) }
          @controller = button_bindings.to_h
          @hotkeys = hotkey_bindings.to_h
        end

        private

        def button?(action) = Input::Controller::BUTTONS.has_key?(action)

        def code(codes, action, name)
          codes.fetch(name) { raise KeyConfig::InvalidConfig, "#{name.inspect} (#{action}) is not a #{@kind} name" }
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
