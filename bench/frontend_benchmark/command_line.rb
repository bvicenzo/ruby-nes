# frozen_string_literal: true

require 'json'

module FrontendBenchmark
  # bench/frontends.rb: runs a ROM in the windowed backend asked for, through a probe that times each present and
  # frame and pushes the test tone (at amplitude 0 without --tone, so the audio stream is fed either way), then prints
  # the medians as one JSON line for `rake bench:frontends` to collect. The window is closed however the run ends.
  class CommandLine
    TONE_FREQUENCY = 440

    def initialize(arguments, output: $stdout)
      @arguments = arguments
      @output = output
    end

    def run
      options = Options.parse(@arguments)
      backend = Backends.load(options.backend)
      console = Ruby::Nes::Console.new(Ruby::Nes::Cartridge::Loader.from_file(options.rom_path))
      frontend = backend.new(hidden: options.hidden)
      probe = Probe.new(
        frontend,
        audio: tone(options, backend),
        samples_per_frame: backend::SAMPLES_PER_FRAME,
        frames: options.frames
      )
      Ruby::Nes::Frontends::Driver.new(console:, frontend: probe).run
      @output.puts(JSON.generate(measurement(options, probe)))
    ensure
      frontend&.close
    end

    private

    def tone(options, backend)
      SquareWave.new(frequency: TONE_FREQUENCY, sample_rate: backend::SAMPLE_RATE, amplitude: options.tone_amplitude)
    end

    def measurement(options, probe)
      frames = Summary.new(probe.frame_seconds)

      {
        backend: options.backend,
        configuration: CpuBenchmark::Configuration.current,
        frames: probe.present_seconds.size,
        present_milliseconds: Summary.new(probe.present_seconds).median_milliseconds,
        frame_milliseconds: frames.median_milliseconds,
        frames_per_second: frames.per_second,
        ruby: RUBY_DESCRIPTION
      }
    end
  end
end
