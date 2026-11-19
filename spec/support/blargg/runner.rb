# frozen_string_literal: true

module Blargg
  # Runs a console frame by frame until its blargg ROM reports a result or `frame_limit` frames have run. A reset
  # request ($81) is honoured "delayed by at least 100 msec from now": RESET_DELAY_FRAMES frames later; the request
  # must then go away before another one counts, since the ROM rewrites the status only once it runs again. The status
  # is read once per frame, so a ROM that went back to $80 and asked again within one frame would not be seen asking
  # twice; no ROM of the manifest does.
  class Runner
    # An NTSC frame lasts 29 780.5 CPU cycles of a 1.789773 MHz clock, 16.6 ms
    # (https://www.nesdev.org/wiki/Cycle_reference_chart): 7 frames are 116 ms.
    RESET_DELAY_FRAMES = 7
    # A minute of emulated time, for the real ROMs: every single ROM run here finishes well before it.
    FRAME_LIMIT = 3600

    # The report's state, code and text when the run stopped, and the frames it took.
    Outcome = Data.define(:state, :code, :text, :frames)

    def initialize(console, frame_limit:)
      @console = console
      @frame_limit = frame_limit
      @report = Report.new(console.cpu_bus)
    end

    def run
      @frames_until_reset = nil
      @reset_pressed = false
      frames = 0
      while frames < @frame_limit
        @console.run_frame
        frames += 1
        state = @report.state
        break if state == :finished

        follow_reset_request(state)
      end
      Outcome.new(state: @report.state, code: @report.code, text: @report.text, frames:)
    end

    private

    def follow_reset_request(state)
      if state != :reset_requested
        @reset_pressed = false
      elsif !@reset_pressed
        count_down_to_reset
      end
    end

    def count_down_to_reset
      @frames_until_reset = (@frames_until_reset || (RESET_DELAY_FRAMES + 1)) - 1
      return unless @frames_until_reset.zero?

      @console.reset
      @reset_pressed = true
      @frames_until_reset = nil
    end
  end
end
