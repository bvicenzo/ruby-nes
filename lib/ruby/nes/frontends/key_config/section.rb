# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      class KeyConfig
        # One section of the config file (plan 18, decision 7): `keys:` names keyboard keys, `gamepad:` gamepad buttons
        # (plan 36). Each of its actions takes an input name or a list of them; an empty list leaves it without one.
        # Actions the section does not name keep their defaults, except the inputs the section gives to another action:
        # the file wins, so `a: z` leaves B, whose default is Z, without a key. Input names are the graphics library's:
        # Frontends::KeyBindings turns them into codes. Off the hot path: read once.
        class Section
          # `name` is the section's in the file, `kind` names its inputs in the errors (`key`, `gamepad button`), and
          # `defaults` maps each action it takes to its default input names.
          def initialize(name:, kind:, defaults:)
            @name = name
            @kind = kind
            @action_names = defaults.keys.map(&:to_s)
            @defaults = defaults
          end

          # Each action to the names of its inputs, from what the file's YAML gave for the section (nil when it has
          # none); raises InvalidConfig when it is not a mapping of actions to input names.
          def bindings(value)
            given = given_names(value || {})
            taken = given.values.flatten
            @defaults.transform_values { it - taken }.merge(given)
          end

          private

          def given_names(value)
            raise InvalidConfig, "#{@name}: maps actions to #{@kind} names" unless value.is_a?(Hash)

            unknown_names = value.keys - @action_names
            raise InvalidConfig, unknown_actions(unknown_names) if unknown_names.any?

            value.to_h { |action, names| [action.to_sym, input_names(action, names)] }
          end

          def unknown_actions(names)
            "#{@name}: not actions: #{names.join(', ')} (it takes #{@action_names.join(', ')})"
          end

          # An input name or a list of them, each once; anything else (YAML's null, booleans, numbers) is an error.
          def input_names(action, names)
            list = names.is_a?(String) ? [names] : names
            return list.uniq if list.is_a?(Array) && list.all?(String)

            expected = "a #{@kind} name or a list of #{@kind} names ([] for none)"
            raise InvalidConfig, "#{@name}: #{action} takes #{expected}, not #{names.inspect}"
          end
        end
      end
    end
  end
end
