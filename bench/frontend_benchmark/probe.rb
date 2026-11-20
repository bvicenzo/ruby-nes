# frozen_string_literal: true

module FrontendBenchmark
  # A frontend wrapped to be measured: it runs while the frontend runs, up to a number of frames when one is given;
  # times each present (RGB conversion, texture upload and drawing, plan 17) and the interval between the starts of
  # consecutive presents (the whole frame, emulation included); and after each present queues a frame's worth of an
  # audio source on the frontend, the audio smoke test.
  class Probe < Ruby::Nes::Frontends::Base
    # Seconds each present took, in frame order.
    attr_reader :present_seconds
    # Seconds from each present's start to the next one's, in frame order: one fewer than the presents.
    attr_reader :frame_seconds

    def initialize(frontend, audio:, samples_per_frame:, frames: nil, clock: Ruby::Nes::Frontends::MonotonicClock)
      super()
      @frontend = frontend
      @audio = audio
      @samples_per_frame = samples_per_frame
      @frames = frames
      @clock = clock
      @present_seconds = []
      @frame_seconds = []
      @previous_start = nil
    end

    def running?
      return false if @frames && @present_seconds.size >= @frames

      @frontend.running?
    end

    def button_states = @frontend.button_states

    def queue_audio(samples) = @frontend.queue_audio(samples)

    def present(frame_buffer)
      start = @clock.call
      @frontend.present(frame_buffer)
      @present_seconds << (@clock.call - start)
      @frame_seconds << (start - @previous_start) if @previous_start
      @previous_start = start
      queue_audio(@audio.samples(@samples_per_frame))
    end
  end
end
