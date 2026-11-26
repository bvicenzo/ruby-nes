# frozen_string_literal: true

module Ruby
  module Nes
    class CommandLine
      # The ROM browser in an open window (plan 37), for CommandLine::Window#browse. While the window runs, each frame
      # the menu (Frontends::Browser::Menu, or Frontends::Browser::EmptyMenu for a folder with no ROM) is told
      # controller 1's buttons, and the window gets a frame of silence, so the audio keeps pacing it (decision 7; while
      # paused the window queues its own), then the menu's picture. A ROM started is played (CommandLine::Game) in
      # the same window on a console of its own, at `audio_sample_rate`, as a game started from the list, whose pause
      # menu leads back to it (plan 38); the window starts over (Frontends::Base#next_screen) on the way in and out.
      # Leaving the game returns to the list, read again from the folder so its marks are fresh, the focus on the game
      # played; closing the window, or quitting from a menu, ends the browser. The list's own menu (the menu's key or
      # buttons, CommandLine::MenuLoop) opens over it, dimmed, and resumes it or quits; the buttons held as the list
      # comes back from a menu or a game are kept from it until let go (Frontends::Base#resume, #next_screen). A game that cannot be started,
      # or whose battery save cannot be written as it closes, is a message in the window and a warning, and the list
      # comes back. Off the hot path: once per menu frame.
      class Browser
        LIST_MENU_ENTRIES = %i[resume quit].freeze

        # `roms` are the Frontends::Browser::Rom of `folder`; the saves and the previews are in `directory` (a
        # Saves::Directory); warnings go to `error_output`.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(frontend:, folder:, roms:, directory:, audio_sample_rate:, error_output:)
          @frontend = frontend
          @folder = folder
          @directory = directory
          @audio_sample_rate = audio_sample_rate
          @error_output = error_output
          @preview = Frontends::Browser::Preview.new(
            cache: Frontends::Browser::PreviewCache.new(directory:, error_output:)
          )
          @button_presses = Frontends::Screens::ButtonPresses.new
          @menu = menu(roms, 0)
        end

        # Raises SystemCallError when the folder cannot be read again.
        def run
          while (rom = chosen_rom)
            @frontend.next_screen
            play(rom)
            return if @frontend.closed?

            @frontend.next_screen
            refresh(rom)
          end
        end

        private

        # The ROM started in the menu, or nil once the window stops.
        def chosen_rom
          while @frontend.running?
            rom = @menu.tick(@frontend.button_states.first)
            return rom if rom

            @frontend.queue_silence unless @frontend.paused?
            @frontend.present(@menu.picture)
            open_list_menu if @frontend.menu_requested?
          end
        end

        # The list's menu over it: QUIT ends the session; RESUME returns to the list, the buttons held kept from it until
        # let go, so the A that chose it starts no ROM. A window closed in it has nothing more done.
        def open_list_menu
          list_menu = Frontends::Pause::Menu.new(entries: LIST_MENU_ENTRIES, background: @menu.picture)
          choice = MenuLoop.run(frontend: @frontend, menu: list_menu)
          return unless choice

          choice.action == :quit ? @frontend.quit : @frontend.resume
        end

        def play(rom)
          game = started_game(rom)
          game.play(@frontend)
        rescue Error, SystemCallError => error
          report(error)
        ensure
          close(game)
        end

        def started_game(rom)
          console = Console.new(Cartridge::Loader.from_file(rom.path), audio_sample_rate: @audio_sample_rate)
          game = Game.new(
            console:, rom_path: rom.path, directory: @directory, error_output: @error_output, back_to_list: true
          )
          game.load
          game
        end

        def close(game)
          game&.close
        rescue SystemCallError => error
          report(error)
        end

        def report(error)
          @frontend.notify(error.message)
          @error_output.puts("ruby-nes: #{error.message}")
        end

        def refresh(rom)
          roms = Frontends::Browser::RomList.scan(@folder, directory: @directory)
          @menu = menu(roms, roms.index { it.path == rom.path } || 0)
        end

        def menu(roms, focus)
          return Frontends::Browser::EmptyMenu.new(folder: @folder) if roms.empty?

          Frontends::Browser::Menu.new(roms:, preview: @preview, focus:, button_presses: @button_presses)
        end
      end
    end
  end
end
