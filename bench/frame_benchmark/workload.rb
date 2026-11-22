# frozen_string_literal: true

require 'digest'

module FrameBenchmark
  # Plays a console frame by frame from power-up, as the window does: the first controller holds the buttons the input
  # script gives the frame's number (counted from 1), the console runs the frame, and its audio is drained. Each run
  # goes on from where the previous one stopped, so a warm-up is a run whose sample is ignored. Only the frames are
  # timed, never the digests.
  class Workload
    MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    # The pixels as Frontends::Headless digests them (plan 16, decision 6), and the audio as signed 16-bit samples.
    PIXEL_FORMAT = 'S<*'
    SAMPLE_FORMAT = 's<*'

    # A console of the ROM file with audio at the window's sample rate, played by the input script file.
    def self.from_files(rom:, input:)
      input_script = Ruby::Nes::Frontends::InputScript.parse(File.read(input))
      cartridge = Ruby::Nes::Cartridge::Loader.from_file(rom)
      new(Ruby::Nes::Console.new(cartridge, audio_sample_rate: Ruby::Nes::Audio::SAMPLE_RATE), input_script:)
    end

    def initialize(console, input_script:, clock: MONOTONIC_CLOCK)
      @console = console
      @input_script = input_script
      @clock = clock
      @frame_number = Ruby::Nes::Frontends::InputScript::FIRST_FRAME
      @audio = Digest::SHA256.new
    end

    def run(frames:)
      seconds = 0.0
      frames.times { seconds += play_frame }
      Sample.new(frames:, seconds:)
    end

    def frame_digest = Digest::SHA256.hexdigest(@console.ppu.frame_buffer.pack(PIXEL_FORMAT))

    def audio_digest = @audio.hexdigest

    private

    def play_frame
      started_at = @clock.call
      @console.controllers.first.buttons = @input_script.buttons_at(@frame_number)
      @console.run_frame
      samples = @console.audio_samples
      seconds = @clock.call - started_at
      @audio.update(samples.pack(SAMPLE_FORMAT))
      @frame_number += 1
      seconds
    end
  end
end
