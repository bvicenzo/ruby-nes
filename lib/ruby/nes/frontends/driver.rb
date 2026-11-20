# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The loop every frontend shares (plan 16): while the frontend runs, the buttons it reports go to the console's
      # two controllers, the console runs a frame, and the frontend gets the frame the PPU completed. The console is
      # reset first when the frontend asks; while the frontend is paused no frame runs and it gets the last completed
      # frame again (plan 18, decision 5). Off the hot path: once per frame.
      class Driver
        def initialize(console:, frontend:)
          @console = console
          @frontend = frontend
        end

        def run
          while @frontend.running?
            @console.reset if @frontend.reset_requested?
            run_frame unless @frontend.paused?
            @frontend.present(@console.ppu.frame_buffer)
          end
        end

        private

        def run_frame
          hold_buttons
          @console.run_frame
        end

        def hold_buttons
          @console.controllers.zip(@frontend.button_states) { |controller, buttons| controller.buttons = buttons }
        end
      end
    end
  end
end
