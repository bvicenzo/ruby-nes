# frozen_string_literal: true

require 'yaml'

module Ruby
  module Nes
    module Frontends
      # The buttons the headless frontend holds on the first controller, frame by frame (plan 16, decision 3). Written
      # in YAML, frame numbers from 1 to lists of button names (Input::Controller::BUTTONS):
      #
      #   60: [start]
      #   61: []
      #   120: [a, right]
      #
      # holds Start during frame 60 only, then A and Right from frame 120 on: an entry's buttons stay held until the
      # next entry. Before the first entry, and in an empty script, nothing is held. Off the hot path: one lookup per
      # frame.
      class InputScript
        # The script cannot be read: the message says why.
        class InvalidScript < Error; end

        FIRST_FRAME = 1

        # The script in a YAML text; raises InvalidScript when it is not one.
        def self.parse(text)
          document = load_yaml(text)
          return EMPTY if document.nil?
          raise InvalidScript, 'an input script maps frame numbers to lists of buttons' unless document.is_a?(Hash)

          document.each_key { ensure_frame(it) }
          new(document.to_h { |frame, names| [frame, buttons(frame, names)] })
        end

        def self.load_yaml(text)
          YAML.safe_load(text)
        rescue Psych::Exception => error
          raise InvalidScript, "the input script cannot be loaded as YAML: #{error.message}"
        end

        def self.ensure_frame(frame)
          return if frame.is_a?(Integer) && frame >= FIRST_FRAME

          raise InvalidScript, "#{frame.inspect} is not a frame number (an integer from #{FIRST_FRAME})"
        end

        def self.buttons(frame, names)
          raise InvalidScript, "the buttons of frame #{frame} are not a list" unless names.is_a?(Array)

          names.inject(0) { |held, name| held | button(name) }
        end

        def self.button(name)
          Input::Controller::BUTTONS.fetch(name.to_s.to_sym) do
            raise InvalidScript, "#{name.inspect} is not a button (#{Input::Controller::BUTTONS.keys.join(', ')})"
          end
        end

        private_class_method :load_yaml, :ensure_frame, :buttons, :button

        # Frame numbers to the buttons held from them on, each a mask of Input::Controller::BUTTONS.
        def initialize(entries)
          @entries = entries.sort.reverse.freeze
        end

        # The buttons held during a frame: the latest entry's at or before it, or none.
        def buttons_at(frame_number)
          _frame, held = @entries.find { |frame, _held| frame <= frame_number }
          held || 0
        end

        # The script that holds nothing, on any frame.
        EMPTY = new({})
      end
    end
  end
end
