# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The loop every frontend shares (plan 16): while the frontend runs, the buttons it reports go to the console's
      # two controllers, the console runs a frame, and the frontend gets the frame the PPU completed. Off the hot path:
      # once per frame.
      class Driver
        def initialize(console:, frontend:)
          @console = console
          @frontend = frontend
        end

        def run
          while @frontend.running?
            hold_buttons
            @console.run_frame
            @frontend.present(@console.ppu.frame_buffer)
          end
        end

        private

        def hold_buttons
          @console.controllers.zip(@frontend.button_states) { |controller, buttons| controller.buttons = buttons }
        end
      end
    end
  end
end
