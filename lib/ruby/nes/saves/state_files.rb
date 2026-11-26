# frozen_string_literal: true

module Ruby
  module Nes
    module Saves
      # A game's save states on disk (plan 35, decision 7): each slot, 0 to SLOTS - 1, is `<slot>.state` with its
      # picture, `<slot>.png`, beside it, in the folder Saves::Directory gives the ROM, asked for when first needed.
      # Both are written atomically (Saves::AtomicFile). The latest slot is the one whose state was written last, the
      # lower of a tie (decision 5). Off the hot path.
      class StateFiles
        SLOTS = 10
        STATE_EXTENSION = '.state'
        PICTURE_EXTENSION = '.png'

        # `directory` is a Saves::Directory; `rom_path` names the game.
        def initialize(directory:, rom_path:)
          @directory = directory
          @rom_path = rom_path
          @folder = nil
        end

        # Writes the state's bytes and its picture's (a PNG) in `slot`, the picture first, so a write that fails leaves
        # the older state; raises SystemCallError when it cannot, and Saves::Error when the folder cannot be found.
        def write(slot, state:, picture:)
          AtomicFile.write(path(slot, PICTURE_EXTENSION)) { it.write(picture) }
          AtomicFile.write(state_path(slot)) { it.write(state) }
        end

        # The state's bytes in `slot`, or nil when it has none; raises SystemCallError when it cannot be read.
        def read(slot)
          File.binread(state_path(slot))
        rescue Errno::ENOENT
          nil
        end

        # The slot of the state written last, or nil when there is none.
        def latest_slot = written_slots.max_by { [File.mtime(state_path(it)), -it] }

        # The slots that hold a state, in order.
        def written_slots = SLOTS.times.select { File.file?(state_path(it)) }

        private

        def state_path(slot) = path(slot, STATE_EXTENSION)

        def path(slot, extension) = File.join(folder, "#{slot}#{extension}")

        def folder = @folder ||= @directory.states_folder(@rom_path)
      end
    end
  end
end
