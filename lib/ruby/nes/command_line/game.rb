# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # A game played in an open window (plan 37, out of CommandLine::Window, which plays one; CommandLine::Browser
      # plays one after another in the same window). `load` puts the game's battery save (plan 34) into the console,
      # before the window opens for `ruby-nes ROM`, through a Saves::BatteryKeeper; `play` runs the console in the
      # frontend through Frontends::Driver until it stops, the driver telling the keeper each frame and handing each
      # state action to the game's Saves::StateSlots (plan 35), the frame on screen drawn as its picture by
      # Frontends::Screenshot, and opening the pause menu (CommandLine::Pause, plan 38) with those slots when the
      # window asks for it; `close` writes the save, however the game ended. A save refused by `load` is never written
      # over. Off the hot path.
      class Game
        # The game of `console`, the ROM at `rom_path`, whose saves are in `directory` (a Saves::Directory); warnings go
        # to `error_output`. `back_to_list` when it was started from the ROM list, so its pause menu offers the way
        # back.
        def initialize(console:, rom_path:, directory:, error_output:, back_to_list: false)
          @console = console
          @rom_path = rom_path
          @directory = directory
          @error_output = error_output
          @back_to_list = back_to_list
          @battery_keeper = nil
        end

        # Raises Saves::InvalidSave or SystemCallError when the save cannot be loaded.
        def load
          @battery_keeper = Saves::BatteryKeeper
            .for(console: @console, directory: @directory, rom_path: @rom_path, error_output: @error_output)
            .tap(&:load)
        end

        # Runs the game in `frontend` (Frontends::Base) until it stops.
        def play(frontend)
          states = state_slots
          pause_menu = Pause.new(console: @console, slots: states, back_to_list: @back_to_list)
          Frontends::Driver.new(console: @console, frontend:, frame_observer: @battery_keeper, states:, pause_menu:).run
        end

        # Writes the save; raises SystemCallError when it cannot.
        def close
          @battery_keeper&.close
        end

        private

        def state_slots
          Saves::StateSlots.for(
            console: @console,
            directory: @directory,
            rom_path: @rom_path,
            picture: Frontends::Screenshot,
            error_output: @error_output
          )
        end
      end
    end
  end
end
