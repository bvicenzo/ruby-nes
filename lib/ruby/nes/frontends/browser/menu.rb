# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      module Browser
        # The ROM browser's menu (plan 37, decision 6), told each frame the buttons held on controller 1 (the keyboard
        # and gamepad 0, Frontends::Players): up and down move the focus a ROM, left and right a page of the list's
        # rows, as Browser::ButtonPresses presses them; A or Start start the ROM in focus when ruby-nes can run it. The
        # preview takes the focus when it lands on another ROM, and only then, and is told every frame. Its picture is
        # Browser::Screen's, with the reason the ROM in focus cannot be run, its own or the preview's. A folder with no
        # ROM is Browser::EmptyMenu's. Off the hot path: once per menu frame.
        class Menu
          BUTTONS = Input::Controller::BUTTONS
          START = Bits.set_flag(BUTTONS.fetch(:a), BUTTONS.fetch(:start))
          # What each direction does to the cursor (Browser::Cursor): a ROM, or a page of the list's rows.
          MOVES = {
            BUTTONS.fetch(:up) => ->(cursor) { cursor.move(-1) },
            BUTTONS.fetch(:down) => ->(cursor) { cursor.move(1) },
            BUTTONS.fetch(:left) => ->(cursor) { cursor.page(-1) },
            BUTTONS.fetch(:right) => ->(cursor) { cursor.page(1) }
          }.freeze

          # `roms` are at least one Browser::Rom, the one at `focus` in focus; `preview` is a Browser::Preview.
          # `button_presses` outlives a menu, so a button held as a game ends is no new press.
          def initialize(roms:, preview:, focus: 0, button_presses: ButtonPresses.new)
            @roms = roms
            @preview = preview
            @screen = Screen.new
            @button_presses = button_presses
            @cursor = Cursor.new(size: roms.size, rows: Screen::LIST_ROWS).tap { it.move(focus) }
            @preview.focus(focus_rom)
          end

          # The ROM to start, from the mask of the buttons held on controller 1 in this frame
          # (Input::Controller::BUTTONS), or nil.
          def tick(buttons)
            presses = @button_presses.presses(buttons)
            move(presses)
            @preview.tick
            focus_rom if presses.anybits?(START) && focus_rom.playable?
          end

          # The screen (docs/architecture.md, Frame buffer contract).
          def picture
            @screen.list(
              roms: @roms,
              cursor: @cursor,
              preview_frame: @preview.frame_buffer,
              problem: focus_rom.problem || @preview.problem
            )
          end

          private

          def focus_rom = @roms.fetch(@cursor.focus)

          def move(presses)
            focus = @cursor.focus
            MOVES.each { |button, move| move.call(@cursor) if presses.anybits?(button) }
            @preview.focus(focus_rom) unless @cursor.focus == focus
          end
        end
      end
    end
  end
end
