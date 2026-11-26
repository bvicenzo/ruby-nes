# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Pause
        # A menu over a paused screen (plan 38): the pause menu over a game and the ROM list's menu. Told each frame the
        # buttons pressed on controller 1, it gives what the player chose (Pause::Choice) once they have: B is
        # Choice::RESUME, SAVE STATE and LOAD STATE open the slot picker (Pause::SlotPicker), where B returns to the
        # entries and a slot chosen is the choice; LOAD STATE cannot be chosen while no slot holds a state. Its picture
        # is Pause::Screen's menu over the screen it opened on, dimmed once (Screens::Shade), or the slot picker's. Off
        # the hot path: once per menu frame.
        class Menu
          LABELS = {
            resume: 'RESUME',
            save_state: 'SAVE STATE',
            load_state: 'LOAD STATE',
            reset: 'RESET',
            back_to_list: 'BACK TO LIST',
            quit: 'QUIT'
          }.freeze
          STATE_ACTIONS = %i[save_state load_state].freeze
          TITLE = 'PAUSED'

          # `entries` are keys of LABELS, in order; `background` is the frame buffer of the screen paused. `slots`, the
          # game's Saves::StateSlots, are asked only when the entries include a state action.
          def initialize(entries:, background:, slots: nil)
            @slots = slots
            unavailable = entries.include?(:load_state) && slots.written_slots.empty? ? [:load_state] : []
            @choices = Screens::Choices.new(entries:, unavailable:)
            @background = Screens::Shade.dim(background)
            @screen = Screen.new
            @picker = nil
            @state_action = nil
          end

          # The Pause::Choice made, or nil, from the mask of the buttons pressed on controller 1 in this frame.
          def tick(presses)
            return choose_slot(presses) if @picker

            entry = @choices.tick(presses)
            return Choice::RESUME if entry == Screens::Choices::BACK
            return open_picker(entry) if STATE_ACTIONS.include?(entry)

            Choice.new(action: entry, slot: nil) if entry
          end

          # The screen (docs/architecture.md, Frame buffer contract).
          def picture
            return @picker.picture if @picker

            @screen.menu(background: @background, title: TITLE, choices: @choices, labels: LABELS)
          end

          private

          def open_picker(action)
            @state_action = action
            @picker = SlotPicker.new(action:, slots: @slots)
            nil
          end

          # The slot chosen in the picker as a Choice, or nil; B closes the picker.
          def choose_slot(presses)
            slot = @picker.tick(presses)
            return close_picker if slot == Screens::Choices::BACK

            Choice.new(action: @state_action, slot:) if slot
          end

          def close_picker
            @picker = nil
          end
        end
      end
    end
  end
end
