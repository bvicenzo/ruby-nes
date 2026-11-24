# frozen_string_literal: true

require 'json'

module FrameBenchmark
  # `bench/frame.rb`: plays the ROM with the input script and audio at the window's sample rate, and prints the
  # measurement as one JSON line.
  class CommandLine
    MISSING_ROM = 'Local ROM absent (%<path>s): place a dump of your own cartridge there (never committed)'

    def initialize(arguments, output: $stdout)
      @arguments = arguments
      @output = output
    end

    def run
      options = Options.parse(@arguments)
      raise MissingRom, format(MISSING_ROM, path: options.rom) unless File.exist?(options.rom)

      workload = Workload.from_files(rom: options.rom, input: options.input)
      summary = session(options, workload).measure
      @output.puts(JSON.generate(Measurement.to_h(summary, workload)))
    end

    private

    def session(options, workload)
      Session.new(
        workload:,
        warm_up_frames: options.warm_up_frames,
        frames_per_run: options.frames_per_run,
        measured_runs: options.measured_runs
      )
    end
  end
end
