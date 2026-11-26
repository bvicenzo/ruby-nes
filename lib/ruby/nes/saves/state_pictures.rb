# frozen_string_literal: true

module Ruby
  module Nes
    module Saves
      # The pictures of a game's save state slots, for the pause menu's slot picker (plan 38, decision 4): the frame on
      # screen at the moment saved, read from the state itself (Saves::ConsoleState), so its palette indices are exact.
      # The state is restored into a console of its own, built when first needed from the playing console's cartridge
      # and sound, which is left alone. A slot with no state, a state that cannot be read, one ruby-nes refuses, or a
      # states folder that cannot be found have no picture. Off the hot path: building a console takes 1-3 ms and
      # restoring a state about 4 ms (plan 37's previews).
      class StatePictures
        # The pictures of `console`'s game, whose states are `files` (Saves::StateFiles).
        def initialize(console:, files:)
          @console = console
          @files = files
          @state = nil
          @scratch_console = nil
        end

        # The frame buffer of the moment saved in `slot`, or nil.
        def picture(slot)
          bytes = @files.read(slot)
          return unless bytes

          state.restore(bytes)
          @scratch_console.ppu.frame_buffer
        rescue Error, SystemCallError
          nil
        end

        private

        def state
          @scratch_console ||= Console.new(@console.cartridge, audio_sample_rate: @console.audio_sample_rate)
          @state ||= ConsoleState.new(@scratch_console)
        end
      end
    end
  end
end
