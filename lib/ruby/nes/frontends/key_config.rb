# frozen_string_literal: true

require 'yaml'
require_relative 'hotkeys'
require_relative 'key_config/section'

module Ruby
  module Nes
    module Frontends
      # The window's controls as the config file sets them (plan 18, decision 7; plan 36), in YAML:
      #
      #   keys:
      #     a: x
      #     b: [z, left_control]
      #     pause: space
      #   gamepad:
      #     a: right_face_right
      #   gamepad_mappings: "03000000790000001100000010010000,USB Gamepad,a:b2,b:b1,...,platform:Linux,"
      #
      # `keys:` binds each action, a controller button (Input::Controller::BUTTONS) or a hotkey (Hotkeys::ACTIONS), to
      # keyboard keys; `gamepad:` binds the controller buttons only to gamepad buttons, hotkeys on the pad being plan
      # 38's (plan 36, decision 3). Both follow KeyConfig::Section's rules, from DEFAULTS and GAMEPAD_DEFAULTS. Names
      # are the graphics library's: Frontends::KeyBindings turns them into codes. `gamepad_mappings:` is text in the SDL
      # GameControllerDB format, one pad per line, for pads the library does not know (plan 36, decision 4). Off the
      # hot path: read once.
      class KeyConfig
        # The file cannot be used: the message says why.
        class InvalidConfig < Error; end

        KEYS = 'keys'
        GAMEPAD = 'gamepad'
        GAMEPAD_MAPPINGS = 'gamepad_mappings'
        SECTIONS = [KEYS, GAMEPAD, GAMEPAD_MAPPINGS].freeze
        DEFAULTS = {
          a: ['x'],
          b: ['z'],
          select: ['right_shift'],
          start: ['enter'],
          up: ['up'],
          down: ['down'],
          left: ['left'],
          right: ['right'],
          pause: ['p'],
          reset: ['r'],
          quit: ['escape'],
          frame_rate: ['f'],
          # The save states' keys, as several emulators lay them out (plan 35, decision 3).
          save_state: ['f5'],
          load_state: ['f7'],
          previous_slot: ['f6'],
          next_slot: ['f8']
        }.freeze
        # raylib's names for a standard pad's buttons, by position (plan 36, decision 1): on a SNES pad A (right) is
        # A and B (bottom) is B, X (top) repeats A and Y (left) repeats B; the D-pad is the left face.
        GAMEPAD_DEFAULTS = {
          a: %w[right_face_right right_face_up],
          b: %w[right_face_down right_face_left],
          select: ['middle_left'],
          start: ['middle_right'],
          up: ['left_face_up'],
          down: ['left_face_down'],
          left: ['left_face_left'],
          right: ['left_face_right']
        }.freeze
        KEY_SECTION = Section.new(name: KEYS, kind: 'key', defaults: DEFAULTS)
        GAMEPAD_SECTION = Section.new(name: GAMEPAD, kind: 'gamepad button', defaults: GAMEPAD_DEFAULTS)

        # Each action to the names of its keys, and each controller button to the names of its gamepad buttons.
        attr_reader :keys, :gamepad_buttons
        # The extra gamepad mappings' text, or nil.
        attr_reader :gamepad_mappings

        # The config in a YAML text; raises InvalidConfig when it is not one.
        def self.parse(text)
          document = sections(load_yaml(text) || {})
          new(
            keys: KEY_SECTION.bindings(document[KEYS]),
            gamepad_buttons: GAMEPAD_SECTION.bindings(document[GAMEPAD]),
            gamepad_mappings: mappings(document[GAMEPAD_MAPPINGS])
          )
        end

        def self.load_yaml(text)
          YAML.safe_load(text)
        rescue Psych::Exception => error
          raise InvalidConfig, "the config cannot be loaded as YAML: #{error.message}"
        end

        def self.sections(document)
          raise InvalidConfig, "the config is a mapping of sections: #{SECTIONS.join(', ')}" unless document.is_a?(Hash)

          other_sections = document.keys - SECTIONS
          raise InvalidConfig, "unknown sections: #{other_sections.join(', ')}" if other_sections.any?

          document
        end

        def self.mappings(text)
          return text if text.nil? || text.is_a?(String)

          raise InvalidConfig, "#{GAMEPAD_MAPPINGS}: takes the text of SDL GameControllerDB lines, not #{text.inspect}"
        end

        private_class_method :load_yaml, :sections, :mappings

        def initialize(keys:, gamepad_buttons:, gamepad_mappings:)
          @keys = keys.freeze
          @gamepad_buttons = gamepad_buttons.freeze
          @gamepad_mappings = gamepad_mappings
        end

        # The actions left without a key. Actions without a gamepad button are not named: a person without a pad
        # would always see them (plan 36, decision 4).
        def unbound_actions = @keys.select { |_action, names| names.empty? }.keys
      end
    end
  end
end
