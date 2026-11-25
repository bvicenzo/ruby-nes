# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      class Driver
        # The frame observer of a run that has none (the headless frontend): told every frame, it does nothing.
        module NoFrameObserver
          def self.frame_ran = nil
        end
      end
    end
  end
end
