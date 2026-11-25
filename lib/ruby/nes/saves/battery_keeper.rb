# frozen_string_literal: true

module Ruby
  module Nes
    module Saves
      # Keeps a game's battery save in step with the console's battery-backed PRG RAM while the window plays (plan 34):
      # `load` puts the save into the console before the first frame; `frame_ran`, told after each frame the driver
      # runs, writes the RAM back every FRAMES_BETWEEN_WRITES frames, and `close` once more when the run ends, each time
      # only when the RAM changed since the load or the last write (decisions 4 and 6). The comparison of 8 KiB, every
      # few seconds, keeps the bus's hot path out of it; a write with its `fsync` took about 2 ms (plan 34). A periodic
      # write that fails is a warning, and the next interval tries again: the game goes on with its RAM intact. The
      # last write, in `close`, raises. `.for` gives a console without battery RAM Saves::NoBattery, which does
      # nothing, before the saves directory is asked anything, so the window never asks.
      class BatteryKeeper
        # About 5 seconds at 60.0988 frames per second: what a killed process can lose at most (decision 4).
        FRAMES_BETWEEN_WRITES = 300

        # The keeper of `console`'s battery RAM in the save `directory` (a Saves::Directory) keeps for the ROM at
        # `rom_path`, or NoBattery; warnings go to `error_output`.
        def self.for(console:, directory:, rom_path:, error_output:)
          return NoBattery unless console.battery_ram

          new(console:, file: BatteryFile.new(directory.battery_save_path(rom_path)), error_output:)
        end

        # `file` is a Saves::BatteryFile.
        def initialize(console:, file:, error_output:)
          @console = console
          @file = file
          @error_output = error_output
          @frames_since_write = 0
          @last_written_ram = nil
        end

        # Puts the file's save, when there is one, into the console; raises what the file raises (InvalidSave,
        # SystemCallError), leaving the RAM untouched.
        def load
          save = @file.read
          @console.battery_ram = save if save
          @last_written_ram = @console.battery_ram
        end

        def frame_ran
          @frames_since_write += 1
          return if @frames_since_write < FRAMES_BETWEEN_WRITES

          @frames_since_write = 0
          write_when_changed
        rescue SystemCallError => error
          @error_output.puts("ruby-nes: the battery save was not written: #{error.message}")
        end

        # Raises SystemCallError when the save cannot be written.
        def close = write_when_changed

        private

        def write_when_changed
          battery_ram = @console.battery_ram
          return if battery_ram == @last_written_ram

          @file.write(battery_ram)
          @last_written_ram = battery_ram
        end
      end
    end
  end
end
