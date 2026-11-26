# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The loop every frontend shares (plan 16): while the frontend runs, the buttons it reports go to the console's
      # two controllers, the console runs a frame, and the frontend gets the frame's audio samples, then the frame the
      # PPU completed, so a frontend paced by its audio has them queued when it waits (plan 24). The console is reset
      # first when the frontend asks; while the frontend is paused no frame runs and it gets the last completed frame
      # again (plan 18, decision 5). After each frame it runs, the frame observer is told `frame_ran` (the window's
      # battery save keeper, plan 34); without one, NoFrameObserver. A save state action the frontend asks for goes to
      # the states (the window's Saves::StateSlots, plan 35) with the frontend, after the reset and before the frame,
      # paused or not; without states, NoStates. Off the hot path: once per frame.
      class Driver
        def initialize(console:, frontend:, frame_observer: NoFrameObserver, states: NoStates)
          @console = console
          @frontend = frontend
          @frame_observer = frame_observer
          @states = states
        end

        def run
          while @frontend.running?
            @console.reset if @frontend.reset_requested?
            perform_state_action
            run_frame unless @frontend.paused?
            @frontend.present(@console.ppu.frame_buffer)
          end
        end

        private

        def perform_state_action
          action = @frontend.state_action
          @states.perform(action, @frontend) if action
        end

        def run_frame
          hold_buttons
          @console.run_frame
          @frontend.queue_audio(@console.audio_samples)
          @frame_observer.frame_ran
        end

        def hold_buttons
          @console.controllers.zip(@frontend.button_states) { |controller, buttons| controller.buttons = buttons }
        end
      end
    end
  end
end

require_relative 'driver/no_frame_observer'
require_relative 'driver/no_states'
