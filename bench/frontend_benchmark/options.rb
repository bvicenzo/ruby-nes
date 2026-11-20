# frozen_string_literal: true

require 'optparse'

module FrontendBenchmark
  # The arguments of bench/frontends.rb (plan 17, decision 2): one ROM and the backend to run it in; without --frames
  # (at least 2) it runs until the window closes (the manual check), --tone gives the audio smoke test's tone an
  # amplitude (0, silence, without it), and --hidden hides the window (the specs; a measurement keeps it visible, as a
  # player sees it).
  Options = Data.define(:rom_path, :backend, :frames, :tone_amplitude, :hidden) do
    def self.parse(arguments)
      options = { backend: nil, frames: nil, tone_amplitude: Options::SILENT, hidden: false }
      rom_paths = parser(options).parse(arguments)
      ensure_one_rom(rom_paths)
      raise OptionParser::MissingArgument, '--backend' unless options[:backend]

      new(rom_path: rom_paths.first, **options)
    end

    def self.parser(options)
      OptionParser.new do |parser|
        parser.banner = "Usage: ruby [--yjit | --zjit] bench/frontends.rb ROM --backend #{Backends::NAMES.join('|')}"
        parser.on('--backend NAME', Backends::NAMES, 'The windowed backend') { |name| options[:backend] = name }
        parser.on('--frames COUNT', OptionParser::DecimalInteger, 'Frames to run') do |count|
          options[:frames] = at_least_two(count)
        end
        parser.on('--tone', 'Play a 440 Hz tone through the audio stream') do
          options[:tone_amplitude] = Options::TONE_AMPLITUDE
        end
        parser.on('--hidden', 'Hide the window') { options[:hidden] = true }
      end
    end

    # OptionParser puts the option's name in front of the message: "invalid argument: --frames 1 (at least 2)".
    def self.at_least_two(count)
      return count if count >= Options::MINIMUM_FRAMES

      raise OptionParser::InvalidArgument, "#{count} (at least #{Options::MINIMUM_FRAMES})"
    end

    def self.ensure_one_rom(rom_paths)
      raise OptionParser::MissingArgument, 'ROM' if rom_paths.empty?
      raise OptionParser::NeedlessArgument, rom_paths.drop(1).join(' ') if rom_paths.size > 1
    end

    private_class_method :parser, :at_least_two, :ensure_one_rom
  end

  # The tone's amplitude in signed 16-bit samples: a quarter of full scale with --tone, none without it.
  Options::TONE_AMPLITUDE = 8_000
  Options::SILENT = 0
  # A frame time is the interval between two presents, so a measured run has at least two frames; `rake
  # bench:frontends` runs 600 (plan 17: the median over 600 frames).
  Options::MINIMUM_FRAMES = 2
  Options::MEASURED_FRAMES = 600
end
