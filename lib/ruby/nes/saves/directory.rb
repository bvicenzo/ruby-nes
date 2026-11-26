# frozen_string_literal: true

module Ruby
  module Nes
    module Saves
      # Where ruby-nes keeps what it saves (plan 34, decision 1): `ruby-nes` under the user's data directory of the XDG
      # Base Directory Specification (https://specifications.freedesktop.org/basedir/latest/). "If $XDG_DATA_HOME is
      # either not set or empty, a default equal to $HOME/.local/share should be used", and a relative path there is
      # "invalid" and ignored. The home directory is Ruby's (`Dir.home`: HOME, else the user's account), as the key
      # config's `~` is, and must be an absolute path. Both are read when a path is asked, so a run that saves nothing
      # never needs them. A battery save is named after the ROM's file name, its extension replaced with `.sav` (plan
      # 34, decision 2), as other emulators name theirs; a game's save states live in a folder named after it too (plan
      # 35, decision 7).
      class Directory
        APPLICATION = 'ruby-nes'
        DEFAULT_DATA_HOME = ['.local', 'share'].freeze
        BATTERY_SAVES = 'saves'
        BATTERY_SAVE_EXTENSION = '.sav'
        STATES = 'states'

        # `home` answers the home directory when called.
        def initialize(environment: ENV, home: -> { Dir.home })
          @environment = environment
          @home = home
        end

        # The folder every save lives under; raises Error when neither XDG_DATA_HOME nor the home directory is an
        # absolute path.
        def root = File.join(data_home, APPLICATION)

        # The battery save of the ROM at `rom_path`.
        def battery_save_path(rom_path)
          File.join(root, BATTERY_SAVES, game_name(rom_path) + BATTERY_SAVE_EXTENSION)
        end

        # The folder of the save states of the ROM at `rom_path`.
        def states_folder(rom_path) = File.join(root, STATES, game_name(rom_path))

        private

        # The ROM's file name without its extension.
        def game_name(rom_path) = File.basename(rom_path, '.*')

        def data_home
          data_home = @environment['XDG_DATA_HOME'].to_s
          return data_home if File.absolute_path?(data_home)

          home = @home.call
          return File.join(home, *DEFAULT_DATA_HOME) if File.absolute_path?(home)

          raise Error, "neither XDG_DATA_HOME nor the home directory (#{home.inspect}) is an absolute path"
        end
      end
    end
  end
end
