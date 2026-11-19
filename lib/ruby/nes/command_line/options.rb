# frozen_string_literal: true

require 'optparse'

module Ruby
  module Nes
    class CommandLine
      # The arguments of `ruby-nes` (plan 16, decision 7): one ROM, then options. Frames count from 1, as the headless
      # frontend counts them, and are read in decimal; without --frames it runs 60, one second of emulation. --help
      # and --version only ask for `information` to print, so they need no ROM.
      Options = Data.define(:rom_path, :headless, :frames, :screenshots, :input_path, :information)

      class Options
        USAGE = 'Usage: ruby-nes ROM --headless [--frames COUNT] [--screenshot FRAME:PATH]... [--input SCRIPT]'
        DEFAULT_FRAMES = 60
        FIRST_FRAME = 1
        # A frame number, a colon, then the path (which may hold colons of its own).
        SCREENSHOT = /\A(\d+):(.+)\z/
        DECIMAL = 10

        def self.parse(arguments)
          options = { headless: false, frames: DEFAULT_FRAMES, screenshots: {}, input_path: nil, information: nil }
          rom_paths = parser(options).parse(arguments)
          return new(rom_path: nil, **options) if options[:information]

          ensure_one_rom(rom_paths)
          ensure_screenshots_run(options[:screenshots], options[:frames])
          new(rom_path: rom_paths.first, **options)
        end

        def self.parser(options)
          OptionParser.new do |parser|
            parser.banner = USAGE
            parser.on('--headless', 'Run without a window or sound') { options[:headless] = true }
            parser.on('--frames COUNT', OptionParser::DecimalInteger, 'Frames to run') do |count|
              options[:frames] = from_first_frame(count)
            end
            parser.on('--screenshot FRAME:PATH', SCREENSHOT, 'Write a frame as a PNG image') do |_argument, frame, path|
              add_screenshot(options[:screenshots], from_first_frame(Integer(frame, DECIMAL)), path)
            end
            parser.on('--input SCRIPT', 'YAML input script: frame number to buttons held') do |path|
              options[:input_path] = path
            end
            parser.on('--version', 'Print the version') { options[:information] = "ruby-nes #{VERSION}" }
            parser.on('-h', '--help', 'Print this help') { options[:information] = parser.help }
          end
        end

        # OptionParser puts the option's name in front of the message: "invalid argument: --frames 0 (at least 1)".
        def self.from_first_frame(frame)
          return frame if frame >= FIRST_FRAME

          raise OptionParser::InvalidArgument, "#{frame} (at least #{FIRST_FRAME})"
        end

        def self.add_screenshot(screenshots, frame, path)
          return screenshots[frame] = path unless screenshots.has_key?(frame)

          raise OptionParser::InvalidArgument, "#{frame}:#{path} (frame #{frame} is already asked)"
        end

        def self.ensure_one_rom(rom_paths)
          raise OptionParser::MissingArgument, 'ROM' if rom_paths.empty?
          raise OptionParser::NeedlessArgument, rom_paths.drop(1).join(' ') if rom_paths.size > 1
        end

        def self.ensure_screenshots_run(screenshots, frames)
          late_frame = screenshots.keys.find { it > frames }
          return unless late_frame

          raise OptionParser::InvalidArgument, "--screenshot frame #{late_frame} (the run has #{frames} frames)"
        end

        private_class_method :parser, :from_first_frame, :add_screenshot, :ensure_one_rom, :ensure_screenshots_run
      end
    end
  end
end
