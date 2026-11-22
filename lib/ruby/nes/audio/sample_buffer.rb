# frozen_string_literal: true

module Ruby
  module Nes
    module Audio
      # The samples of a frame, in an array allocated once, until the frontend drains them (plan 24). A full buffer
      # drops the new samples: nobody drained it. Its push is called once per sample, about every 37 CPU cycles: no
      # allocation.
      class SampleBuffer
        # A power of two above five frames at 48 kHz (800 samples each): a frame never fills it unless nobody drains.
        DEFAULT_CAPACITY = 4096

        def initialize(capacity: DEFAULT_CAPACITY)
          @samples = Array.new(capacity, 0)
          @size = 0
        end

        def push(sample)
          return if @size == @samples.size

          @samples[@size] = sample
          @size += 1
        end

        # The samples pushed since the last drain, in order, in an array of their own; the buffer is then empty.
        def drain
          drained = @samples.first(@size)
          @size = 0
          drained
        end
      end
    end
  end
end
