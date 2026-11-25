# frozen_string_literal: true

module Ruby
  module Nes
    # What the window keeps between runs (plan 34): the battery-backed saves of the games, under the user's data
    # directory. Like the frontends, outside the core: `lib/ruby/nes.rb` never loads it, and headless runs never use it
    # (plan 34, decision 3). Off the hot path.
    module Saves
      # Base class of every error raised while finding, reading or writing a save.
      class Error < Nes::Error; end

      # A save file that is not a save: a battery save of another size than the cartridge's 8 KiB of PRG RAM.
      class InvalidSave < Error; end
    end
  end
end

require_relative 'saves/directory'
require_relative 'saves/battery_file'
require_relative 'saves/no_battery'
require_relative 'saves/battery_keeper'
