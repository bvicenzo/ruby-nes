# frozen_string_literal: true

module Ruby
  module Nes
    module Frontends
      # Paces a windowed frontend by its audio (plan 24). Each frame's samples are queued, and every whole chunk the
      # stream has room for is submitted at once, without waiting, so a window run unpaced still feeds the speaker.
      # After the present, `wait` submits every whole chunk still queued, each once the stream has room: the stream
      # holds two chunks and frees one as it plays, so the emulator runs at the pace the speaker plays, the audio clock
      # being the master (decision 4). Less than a chunk waits for the next frame; an emulator slower than the speaker
      # never waits, and the stream plays silence between chunks (decision 2). A stream that finds no room within
      # MAXIMUM_POLLS polls (a dead audio device) loses the chunks queued, so the window never freezes. The queue keeps
      # at most MAXIMUM_CHUNKS chunks, dropping the oldest samples. Answers `wait` like Frontends::FramePacing. Off the
      # hot path: once per frame.
      class AudioPacing
        # How long to sleep between two looks at the stream: a chunk of 800 samples plays in about 17 ms.
        POLL_SECONDS = 0.001
        # About two chunks' time: a live stream frees a sub-buffer well before.
        MAXIMUM_POLLS = 34
        MAXIMUM_CHUNKS = 4

        # `stream` answers `room?` and `submit(chunk)` (Frontends::RaylibAudioStream); `sleeper` sleeps the seconds it
        # is given.
        def initialize(stream:, chunk_size:, sleeper: Kernel.method(:sleep))
          @stream = stream
          @chunk_size = chunk_size
          @sleeper = sleeper
          @pending = []
        end

        def queue(samples)
          @pending.concat(samples)
          excess = @pending.size - (MAXIMUM_CHUNKS * @chunk_size)
          @pending.shift(excess) if excess.positive?
          submit_chunk while whole_chunk? && @stream.room?
        end

        # A chunk of silence, for a frame the paused window does not run (plan 24, decision 7).
        def queue_silence = queue(Array.new(@chunk_size, 0))

        # Drops the samples queued and not yet submitted, after a save state is loaded (plan 35, decision 8).
        def clear = @pending.clear

        def wait
          while whole_chunk?
            return @pending.clear unless room_within_limit?

            submit_chunk
          end
        end

        private

        def whole_chunk? = @pending.size >= @chunk_size

        def submit_chunk = @stream.submit(@pending.shift(@chunk_size))

        def room_within_limit?
          MAXIMUM_POLLS.times do
            return true if @stream.room?

            @sleeper.call(POLL_SECONDS)
          end
          @stream.room?
        end
      end
    end
  end
end
