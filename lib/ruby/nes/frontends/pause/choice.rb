# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Pause
        # What the player chose in a menu over a paused screen (plan 38): an entry of Pause::Menu::LABELS, with the
        # slot chosen for :save_state and :load_state, nil for the others.
        Choice = Data.define(:action, :slot)
        # Closing the menu: B, or the menu's key or buttons again.
        Choice::RESUME = Choice.new(action: :resume, slot: nil)
      end
    end
  end
end
