# frozen_string_literal: true

require_relative '../saves'

module Ruby
  module Nes
    module Frontends
      # The ROM browser (plan 37): `ruby-nes` with no ROM lists the ROMs of a folder, previews the game in focus and
      # starts it. Its screen is an NES frame composed in Ruby, 256 × 240 palette indices, drawn by the window like a
      # game's (decision 3), and it is navigated with controller 1's buttons (decision 6). Off the hot path: once per
      # menu frame.
      module Browser
      end
    end
  end
end

require_relative 'browser/pixel_font'
require_relative 'browser/rom_name'
require_relative 'browser/rom'
require_relative 'browser/rom_list'
require_relative 'browser/button_presses'
require_relative 'browser/cursor'
require_relative 'browser/motion_watch'
require_relative 'browser/preview_cache'
require_relative 'browser/preview'
require_relative 'browser/screen'
require_relative 'browser/menu'
require_relative 'browser/empty_menu'
