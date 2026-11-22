# frozen_string_literal: true

module FrameBenchmark
  # One timed run: the frames played and the seconds they took.
  Sample = Data.define(:frames, :seconds)

  class Sample
    def frames_per_second = frames / seconds
  end
end
