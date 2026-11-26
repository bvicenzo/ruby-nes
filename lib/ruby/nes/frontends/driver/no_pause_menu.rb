# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      class Driver
        # The pause menu of a run that has none (the headless frontend, which never asks for it; plan 38): opening it
        # does nothing.
        module NoPauseMenu
          def self.open(_frontend) = nil
        end
      end
    end
  end
end
