# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The keys of a computer keyboard bound to the buttons of a standard controller (plan 17). Built from bindings,
      # a graphics library's key code to a button name of Input::Controller::BUTTONS; several keys may share a button.
      # Opposite directions are not filtered: the core does not filter them either (plan 15, decision 2), the window
      # of plan 18 does. Off the hot path: asked once per frame.
      class Keyboard
        def initialize(bindings)
          unknown_names = bindings.values.uniq - Input::Controller::BUTTONS.keys
          raise ArgumentError, "not controller buttons: #{unknown_names.join(', ')}" if unknown_names.any?

          @bits = bindings.transform_values { Input::Controller::BUTTONS.fetch(it) }
        end

        # The controller's mask, a button held when the block says one of its keys is held: `{ |key_code| held? }`.
        # The block is asked about bound keys only.
        def buttons
          @bits.reduce(0) { |mask, (key_code, bit)| yield(key_code) ? Bits.set_flag(mask, bit) : mask }
        end
      end
    end
  end
end
