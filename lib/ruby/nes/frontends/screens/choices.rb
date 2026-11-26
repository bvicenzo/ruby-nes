# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Screens
        # The entries of a menu, one under the other (plan 38): the pause menu's, the list's menu's, the slot picker's.
        # Told each frame the buttons pressed on controller 1 (Screens::ButtonPresses), up and down move the focus an
        # entry, stopping at the ends; then A or Start choose the entry in focus, unless it is unavailable (drawn grey).
        # B goes back, before anything pressed with it. Off the hot path: once per menu frame.
        class Choices
          BUTTONS = Input::Controller::BUTTONS
          CHOOSE = Bits.set_flag(BUTTONS.fetch(:a), BUTTONS.fetch(:start))
          BACK_BUTTON = BUTTONS.fetch(:b)
          UP = BUTTONS.fetch(:up)
          DOWN = BUTTONS.fetch(:down)
          # What `tick` gives when B is pressed.
          BACK = :back

          # The entries, in order.
          attr_reader :entries

          # `entries` are what the menu offers, at least one, any object; those in `unavailable` cannot be chosen. The
          # one at index `focus` starts in focus.
          def initialize(entries:, unavailable: [], focus: 0)
            @entries = entries
            @unavailable = unavailable
            @cursor = Cursor.new(size: entries.size, rows: entries.size).tap { it.move(focus) }
          end

          # The index of the entry in focus.
          def focus = @cursor.focus

          def available?(entry) = !@unavailable.include?(entry)

          # The entry chosen, BACK, or nil, from the mask of the buttons pressed on controller 1 in this frame
          # (Input::Controller::BUTTONS).
          def tick(presses)
            return BACK if presses.anybits?(BACK_BUTTON)

            @cursor.move(-1) if presses.anybits?(UP)
            @cursor.move(1) if presses.anybits?(DOWN)
            entry = @entries.fetch(focus)
            entry if presses.anybits?(CHOOSE) && available?(entry)
          end
        end
      end
    end
  end
end
