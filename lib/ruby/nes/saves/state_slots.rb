# frozen_string_literal: true

module Ruby
  module Nes
    module Saves
      # The player's save states in the window (plan 35). Of StateFiles::SLOTS slots, the current one is picked with
      # `:previous_slot` and `:next_slot`, wrapping around (decision 3); a game starts on the slot it saved last, or 0
      # (decision 5). `:save_state` writes the console's state (Saves::ConsoleState) and a picture of the frame on
      # screen over the current slot at once (decision 4); `:load_state` brings the console back to it and tells the
      # frontend to drop the audio it queued (decision 8). Every action ends with a message for the frontend to show
      # (decision 9). A file that cannot be written or read, or a states folder that cannot be found, is also a warning
      # on the error output, and the game goes on. Frontends::Driver hands it the frontend's action between frames.
      # Off the hot path.
      class StateSlots
        ACTIONS = %i[save_state load_state previous_slot next_slot].freeze

        # The slots of `console`'s game, the ROM at `rom_path`, in `directory` (a Saves::Directory); `picture` turns a
        # frame buffer into PNG bytes (`png`, Frontends::Screenshot) and warnings go to `error_output`.
        def self.for(console:, directory:, rom_path:, picture:, error_output:)
          new(
            console:,
            state: ConsoleState.new(console),
            files: StateFiles.new(directory:, rom_path:),
            picture:,
            error_output:
          )
        end

        # `state` is the console's Saves::ConsoleState, `files` the game's Saves::StateFiles.
        def initialize(console:, state:, files:, picture:, error_output:)
          @console = console
          @state = state
          @files = files
          @picture = picture
          @error_output = error_output
          @slot = nil
        end

        # The current slot; raises Saves::Error or SystemCallError when the states folder cannot be found.
        def slot = @slot ||= @files.latest_slot || 0

        # Performs one of ACTIONS and tells `frontend` (Frontends::Base) the outcome; raises ArgumentError for another
        # action.
        def perform(action, frontend)
          raise ArgumentError, "not a state action: #{action}" unless ACTIONS.include?(action)

          # Finds the states folder first, so one that cannot be found is "unavailable" for every action, not a save or
          # a load that failed.
          slot
          frontend.notify(outcome(action, frontend))
        rescue Error, SystemCallError => error
          frontend.notify("States unavailable: #{error.message}")
          @error_output.puts("ruby-nes: save states are unavailable: #{error.message}")
        end

        private

        def outcome(action, frontend)
          case action
          when :next_slot then select_slot(slot + 1)
          when :previous_slot then select_slot(slot - 1)
          when :save_state then save
          else load(frontend)
          end
        end

        def select_slot(slot)
          @slot = slot % StateFiles::SLOTS
          "Slot #{@slot}"
        end

        def save
          @files.write(slot, state: @state.encode, picture: @picture.png(@console.ppu.frame_buffer))
          "State #{slot} saved"
        rescue SystemCallError => error
          @error_output.puts("ruby-nes: state #{slot} was not saved: #{error.message}")
          "State #{slot} not saved: #{error.message}"
        end

        def load(frontend)
          bytes = @files.read(slot)
          return "State #{slot} is empty" unless bytes

          @state.restore(bytes)
          frontend.discard_audio
          "State #{slot} loaded"
        rescue InvalidState => error
          "State #{slot} not loaded: #{error.message}"
        rescue SystemCallError => error
          @error_output.puts("ruby-nes: state #{slot} was not loaded: #{error.message}")
          "State #{slot} not loaded: #{error.message}"
        end
      end
    end
  end
end
