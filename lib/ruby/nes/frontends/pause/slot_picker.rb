# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Pause
        # The pause menu's slot picker (plan 38, scope 2): the save state slots, the current one in focus, navigated as
        # a menu's entries (Screens::Choices). To save, every slot can be chosen; to load, only those that hold a state.
        # Its picture is Pause::Screen's, with the picture of the slot in focus, asked of the game's slots' pictures
        # (Saves::StatePictures) the first time the focus lands on a slot that holds a state, and kept while the picker
        # is open (plan 38, decision 4). Off the hot path: once per menu frame; a picture takes a few milliseconds.
        class SlotPicker
          TITLES = { save_state: 'SAVE STATE', load_state: 'LOAD STATE' }.freeze

          # `action` is :save_state or :load_state; `slots` are the game's Saves::StateSlots.
          def initialize(action:, slots:)
            @title = TITLES.fetch(action)
            @written = slots.written_slots
            @pictures = slots.pictures
            @pictures_by_slot = {}
            all_slots = Saves::StateFiles::SLOTS.times.to_a
            unavailable = action == :load_state ? all_slots - @written : []
            @choices = Screens::Choices.new(entries: all_slots, unavailable:, focus: slots.current_slot)
            @screen = Screen.new
            show_focus
          end

          # The slot chosen, Screens::Choices::BACK, or nil, from the mask of the buttons pressed on controller 1 in
          # this frame.
          def tick(presses)
            focus = @choices.focus
            choice = @choices.tick(presses)
            show_focus unless @choices.focus == focus
            choice
          end

          # The screen (docs/architecture.md, Frame buffer contract).
          def picture = @screen.slots(title: @title, choices: @choices, written: @written, picture: @focus_picture)

          private

          def show_focus
            slot = @choices.focus
            @focus_picture = (picture_of(slot) if @written.include?(slot))
          end

          def picture_of(slot) = @pictures_by_slot.fetch(slot) { @pictures_by_slot[slot] = @pictures.picture(slot) }
        end
      end
    end
  end
end
