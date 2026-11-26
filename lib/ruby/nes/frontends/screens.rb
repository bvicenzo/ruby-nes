# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # What the window's menus share (plan 38, out of plan 37's ROM browser): each is an NES frame composed in Ruby,
      # 256 × 240 palette indices drawn by the window like a game's, with text on the 8 × 8 grid in an 8 × 8 font of its
      # own, navigated with controller 1's buttons. Off the hot path: once per menu frame.
      module Screens
      end
    end
  end
end

require_relative 'screens/colours'
require_relative 'screens/pixel_font'
require_relative 'screens/button_presses'
require_relative 'screens/cursor'
require_relative 'screens/canvas'
require_relative 'screens/layout'
require_relative 'screens/shade'
require_relative 'screens/choices'
