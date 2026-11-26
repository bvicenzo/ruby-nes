# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Screens
        # The menus' colours, of the NES palette (Frontends::Palette; plan 37, decision 3): black, white, light grey,
        # red and yellow.
        module Colours
          BACKGROUND = 0x0F
          TEXT = 0x30
          QUIET = 0x10
          WARNING = 0x16
          HIGHLIGHT = 0x28
        end
      end
    end
  end
end
