# frozen_string_literal: true

require_relative '../saves'
require_relative 'screens'

module Ruby
  module Nes
    module Frontends
      # The pause menu (plan 38): over the paused game, dimmed (Screens::Shade), it resumes, saves and loads states
      # through a slot picker, resets, returns to the ROM list and quits. Its screens are NES frames composed in Ruby,
      # as the ROM browser's (plan 37, decision 3). Off the hot path: once per menu frame.
      module Pause
      end
    end
  end
end

require_relative 'pause/choice'
require_relative 'pause/screen'
require_relative 'pause/slot_picker'
require_relative 'pause/menu'
