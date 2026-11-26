# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The controllers' buttons held as a menu closes (plan 38, scope 3), kept from the game until let go: the A that
      # chose RESUME would make Mario jump, a held Start would pause the game. Each button leaves on the first frame it
      # is not held, so holding it again counts. Off the hot path: once per frame.
      class HeldOver
        def initialize
          @buttons = [0, 0]
        end

        # Takes `button_states`, both controllers' masks (`[first, second]`, Frontends::Base#button_states), as held
        # over.
        def hold(button_states)
          @buttons = button_states.dup
        end

        # Both controllers' masks from `button_states`, without the buttons still held over.
        def filter(button_states)
          @buttons = @buttons.zip(button_states).map do |held_over, held|
            released = Bits.clear_flag(held_over, held)
            Bits.clear_flag(held_over, released)
          end
          button_states.zip(@buttons).map { |held, held_over| Bits.clear_flag(held, held_over) }
        end
      end
    end
  end
end
