# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # Inputs bound to the buttons of a standard controller: a keyboard's keys (plan 17) or a gamepad's buttons (plan
      # 36). Built from bindings, a graphics library's input code to a button name of Input::Controller::BUTTONS;
      # several inputs may share a button. Opposite directions are not filtered: the core does not filter them either
      # (plan 15, decision 2), Frontends::Players does. Off the hot path: asked once per frame.
      class Controls
        def initialize(bindings)
          unknown_names = bindings.values.uniq - Input::Controller::BUTTONS.keys
          raise ArgumentError, "not controller buttons: #{unknown_names.join(', ')}" if unknown_names.any?

          @bits = bindings.transform_values { Input::Controller::BUTTONS.fetch(it) }
        end

        # The controller's mask, a button held when the block says one of its inputs is held: `{ |code| held? }`.
        # The block is asked about bound inputs only.
        def buttons
          @bits.reduce(0) { |mask, (code, bit)| yield(code) ? Bits.set_flag(mask, bit) : mask }
        end
      end
    end
  end
end
