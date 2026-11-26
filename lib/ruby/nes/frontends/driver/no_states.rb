# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      class Driver
        # The save states of a run that has none (the headless frontend, plan 35, decision 10): an action asked for does
        # nothing.
        module NoStates
          def self.perform(_action, _frontend) = nil
        end
      end
    end
  end
end
