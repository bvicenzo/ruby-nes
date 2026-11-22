# frozen_string_literal: true

require 'digest'

module Ruby
  module Nes
    module Frontends
      # A frontend with no window and no sound (plan 16), for tests, benchmarks and the command line: it runs a number
      # of frames, counted from 1 (the first frame after power-up is frame 1), holds the input script's buttons on the
      # first controller, writes a PNG screenshot of each frame asked for, and keeps a digest of every frame. With a WAV
      # path it keeps every audio sample and writes them as a WAV file when it closes (plan 24). The same ROM and script
      # give the same digests and the same WAV on every run: the core has no source of randomness.
      class Headless < Base
        # Each frame's SHA-256, hexadecimal, in frame order: of its pixels as 16-bit little-endian integers, since a
        # pixel goes up to 511 (plan 16, decision 6).
        attr_reader :digests

        # `screenshots` maps frame numbers to the paths their PNG images are written to; `wav` is the WAV file's path.
        def initialize(frames:, input_script: InputScript::EMPTY, screenshots: {}, wav: nil)
          super()
          @frames = frames
          @input_script = input_script
          @screenshots = screenshots
          @wav = wav
          @presented = 0
          @digests = []
          @samples = []
        end

        def running? = @presented < @frames

        # The script's buttons for the frame about to run on the first controller; the second holds nothing.
        def button_states
          [@input_script.buttons_at(@presented + 1), 0]
        end

        def present(frame_buffer)
          @presented += 1
          @digests << Digest::SHA256.hexdigest(frame_buffer.pack('S<*'))
          path = @screenshots[@presented]
          write_screenshot(path, frame_buffer) if path
        end

        def queue_audio(samples)
          @samples.concat(samples)
        end

        def close
          File.binwrite(@wav, Wav.encode(@samples, sample_rate: Audio::SAMPLE_RATE)) if @wav
        end

        private

        def write_screenshot(path, frame_buffer)
          rgb = Palette.rgb(frame_buffer)
          File.binwrite(path, Png.encode(width: Ppu::Picture::WIDTH, height: Ppu::Picture::HEIGHT, rgb:))
        end
      end
    end
  end
end
