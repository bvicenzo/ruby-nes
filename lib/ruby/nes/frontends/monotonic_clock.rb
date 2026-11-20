# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # The clock frontends pace and measure frames with (plan 18): seconds that only move forward, whatever happens to
      # the wall clock.
      module MonotonicClock
        def self.call = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
