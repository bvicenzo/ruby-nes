# frozen_string_literal: true

module FrameBenchmark
  # One configuration's measurement as bench/frame.rb and spinel/frames.rb print it, one JSON line that
  # FrameBenchmark::Report turns into a row.
  module Measurement
    def self.to_h(summary, workload)
      {
        configuration: CpuBenchmark::Configuration.current,
        frames_per_second: summary.frames_per_second,
        milliseconds_per_frame: summary.milliseconds_per_frame,
        percent_of_real_time: summary.percent_of_real_time,
        spread: summary.spread,
        frame_digest: workload.frame_digest,
        audio_digest: workload.audio_digest,
        ruby: RUBY_DESCRIPTION
      }
    end
  end
end
