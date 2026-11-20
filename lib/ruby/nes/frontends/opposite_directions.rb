# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # Cancels opposite directions held together on a keyboard (plan 18, decision 3): Left with Right, or Up with Down,
      # reach the controller as neither, the other buttons untouched. NESdev documents no behaviour for them
      # (https://www.nesdev.org/wiki/Standard_controller), and the core does not filter them (plan 15, decision 2). Off
      # the hot path: once per frame.
      module OppositeDirections
        PAIRS = [
          Bits.set_flag(Input::Controller::BUTTONS[:left], Input::Controller::BUTTONS[:right]),
          Bits.set_flag(Input::Controller::BUTTONS[:up], Input::Controller::BUTTONS[:down])
        ].freeze

        # The controller mask (Input::Controller::BUTTONS) with every pair held together released.
        def self.filter(buttons)
          PAIRS.reduce(buttons) { |held, pair| held.allbits?(pair) ? Bits.clear_flag(held, pair) : held }
        end
      end
    end
  end
end
