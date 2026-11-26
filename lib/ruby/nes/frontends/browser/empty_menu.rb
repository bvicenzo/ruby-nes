# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # The ROM browser's menu for a folder with no ROM (plan 37, decision 1), in Browser::Menu's place: nothing to
        # start, and a picture that says so (Browser::Screen#empty). Off the hot path: once per menu frame.
        class EmptyMenu
          def initialize(folder:)
            @picture = Screen.new.empty(folder)
          end

          # Nothing to start, whatever `_buttons` holds.
          def tick(_buttons) = nil

          attr_reader :picture
        end
      end
    end
  end
end
