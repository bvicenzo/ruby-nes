# frozen_string_literal: true

module FrontendBenchmark
  # The pacing the benchmark gives a windowed backend: none, so a present is timed without the wait of
  # Frontends::FramePacing and the frames run as fast as they can (plan 18).
  module Unpaced
    def self.wait = nil
  end
end
