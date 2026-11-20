# frozen_string_literal: true

require 'yaml'
require_relative 'hotkeys'

module Ruby
  module Nes
    module Frontends
      # The keys of the windowed frontend as the config file sets them (plan 18, decision 7), in YAML:
      #
      #   keys:
      #     a: x
      #     b: [z, left_control]
      #     pause: space
      #
      # Each action, a controller button (Input::Controller::BUTTONS) or a hotkey (Hotkeys::ACTIONS), takes a key name
      # or a list of key names; an empty list leaves it without a key. Actions the file does not mention keep their
      # DEFAULTS, except the keys the file gives to another action: the file wins, so `a: z` leaves B, whose default is
      # Z, without a key. `keys:` is the only section. Key names are the graphics library's: Frontends::KeyBindings
      # turns them into key codes. Off the hot path: read once.
      class KeyConfig
        # The file cannot be used: the message says why.
        class InvalidConfig < Error; end

        SECTION = 'keys'
        ACTIONS = (Input::Controller::BUTTONS.keys + Hotkeys::ACTIONS).freeze
        DEFAULTS = {
          a: 'x',
          b: 'z',
          select: 'right_shift',
          start: 'enter',
          up: 'up',
          down: 'down',
          left: 'left',
          right: 'right',
          pause: 'p',
          reset: 'r',
          quit: 'escape',
          frame_rate: 'f'
        }.freeze

        # Each action to the names of its keys.
        attr_reader :keys

        # The config in a YAML text; raises InvalidConfig when it is not one.
        def self.parse(text)
          section = keys_section(load_yaml(text) || {})
          unknown_names = section.keys - ACTIONS.map(&:to_s)
          raise InvalidConfig, "not actions: #{unknown_names.join(', ')}" if unknown_names.any?

          new(section.to_h { |action, names| [action.to_sym, key_names(action, names)] })
        end

        # A key name or a list of them, each once; anything else (YAML's null, booleans, numbers) is an error.
        def self.key_names(action, names)
          list = names.is_a?(String) ? [names] : names
          return list.uniq if list.is_a?(Array) && list.all?(String)

          raise InvalidConfig, "#{action}: takes a key name or a list of key names ([] for none), not #{names.inspect}"
        end

        def self.load_yaml(text)
          YAML.safe_load(text)
        rescue Psych::Exception => error
          raise InvalidConfig, "the config cannot be loaded as YAML: #{error.message}"
        end

        def self.keys_section(document)
          raise InvalidConfig, 'the config is a mapping with a keys: section' unless document.is_a?(Hash)

          other_sections = document.keys - [SECTION]
          raise InvalidConfig, "unknown sections: #{other_sections.join(', ')}" if other_sections.any?

          section = document[SECTION] || {}
          raise InvalidConfig, 'keys: maps actions to key names' unless section.is_a?(Hash)

          section
        end

        private_class_method :key_names, :load_yaml, :keys_section

        # `keys` overrides the defaults of the actions it names, and takes its keys from the others.
        def initialize(keys)
          taken = keys.values.flatten
          @keys = DEFAULTS.transform_values { [it] - taken }.merge(keys).freeze
        end

        # The actions left without a key.
        def unbound_actions = @keys.select { |_action, names| names.empty? }.keys
      end
    end
  end
end
