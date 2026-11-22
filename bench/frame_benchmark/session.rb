# frozen_string_literal: true

module FrameBenchmark
  # One measurement: the warm-up frames played once, untimed, then the measured runs, summarised.
  class Session
    def initialize(workload:, warm_up_frames:, frames_per_run:, measured_runs:)
      @workload = workload
      @warm_up_frames = warm_up_frames
      @frames_per_run = frames_per_run
      @measured_runs = measured_runs
    end

    def measure
      @workload.run(frames: @warm_up_frames) if @warm_up_frames.positive?
      samples = Array.new(@measured_runs) { @workload.run(frames: @frames_per_run) }
      Summary.new(samples)
    end
  end
end
