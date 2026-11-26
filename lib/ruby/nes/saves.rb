# frozen_string_literal: true

module Ruby
  module Nes
    # What the window keeps between runs: the battery-backed saves of the games (plan 34) and their save states (plan
    # 35), under the user's data directory. Like the frontends, outside the core: `lib/ruby/nes.rb` never loads it,
    # and headless runs never use it (plan 34, decision 3; plan 35, decision 10). Off the hot path.
    module Saves
      # Base class of every error raised while finding, reading or writing a save.
      class Error < Nes::Error; end

      # A save file that is not a save: a battery save of another size than the cartridge's 8 KiB of PRG RAM.
      class InvalidSave < Error; end

      # A save state that cannot be restored into the console: the message says why (plan 35, decision 2).
      class InvalidState < Error; end
    end
  end
end

require_relative 'saves/atomic_file'
require_relative 'saves/directory'
require_relative 'saves/shape'
require_relative 'saves/constants_digest'
require_relative 'saves/console_state'
require_relative 'saves/state_files'
require_relative 'saves/state_pictures'
require_relative 'saves/state_slots'
require_relative 'saves/battery_file'
require_relative 'saves/no_battery'
require_relative 'saves/battery_keeper'
