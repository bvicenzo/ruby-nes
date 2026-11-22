# frozen_string_literal: true

require 'optparse'

module Ruby
  module Nes
    class CommandLine
      # The arguments of `ruby-nes` (plan 16, decision 7; plan 18): one ROM, then options. The JIT applies to every run
      # (YJIT by default, plan 18, decision 1); the window takes its scale, its pixel aspect (1, or 8/7) and whether to
      # crop the overscan (plan 18, decision 4), and a config file path (nil for the default one); the headless run
      # takes its frames, screenshots, input script and WAV file. The window plays sound unless --no-audio (plan 24).
      # Each frontend ignores the other's options (plan 18, decision 9). Frames count from 1, as the headless frontend
      # counts them, and numbers are decimal; without --frames it runs 60, one second of emulation. --help and --version
      # only ask for `information` to print, so they need no ROM.
      Options = Data.define(
        :rom_path,
        :jit,
        :headless,
        :scale,
        :pixel_aspect,
        :crop_overscan,
        :config_path,
        :frames,
        :screenshots,
        :input_path,
        :audio,
        :wav_path,
        :information
      )

      class Options
        USAGE = <<~TEXT.chomp
          Usage: ruby-nes ROM [--jit=none|yjit|zjit] [--scale N] [--aspect square|8:7] [--crop-overscan] [--config PATH]
                              [--no-audio]
                 ruby-nes ROM [--jit=none|yjit|zjit] --headless [--frames COUNT] [--screenshot FRAME:PATH]... [--input SCRIPT]
                              [--wav PATH]
        TEXT
        JITS = %w[none yjit zjit].freeze
        DEFAULT_JIT = 'yjit'
        DEFAULT_SCALE = 3
        # A pixel's width over its height: square, or "exactly 8:7" (https://www.nesdev.org/wiki/Overscan).
        PIXEL_ASPECTS = { 'square' => 1, '8:7' => Rational(8, 7) }.freeze
        DEFAULT_FRAMES = 60
        FIRST_FRAME = 1
        MINIMUM_SCALE = 1
        # A frame number, a colon, then the path (which may hold colons of its own).
        SCREENSHOT = /\A(\d+):(.+)\z/
        DECIMAL = 10

        def self.parse(arguments)
          options = {
            jit: DEFAULT_JIT,
            headless: false,
            scale: DEFAULT_SCALE,
            pixel_aspect: PIXEL_ASPECTS.fetch('square'),
            crop_overscan: false,
            config_path: nil,
            frames: DEFAULT_FRAMES,
            screenshots: {},
            input_path: nil,
            audio: true,
            wav_path: nil,
            information: nil
          }
          rom_paths = parser(options).parse(arguments)
          return new(rom_path: nil, **options) if options[:information]

          ensure_one_rom(rom_paths)
          ensure_screenshots_run(options[:screenshots], options[:frames])
          new(rom_path: rom_paths.first, **options)
        end

        def self.parser(options)
          OptionParser.new do |parser|
            parser.banner = USAGE
            parser.on('--jit NAME', JITS, "JIT to run under: #{JITS.join(', ')} (#{DEFAULT_JIT})") do |name|
              options[:jit] = name
            end
            window_options(parser, options)
            headless_options(parser, options)
            parser.on('--version', 'Print the version') { options[:information] = "ruby-nes #{VERSION}" }
            parser.on('-h', '--help', 'Print this help') { options[:information] = parser.help }
          end
        end

        def self.window_options(parser, options)
          parser.on('--scale N', OptionParser::DecimalInteger, "Window scale (#{DEFAULT_SCALE})") do |scale|
            options[:scale] = at_least(MINIMUM_SCALE, scale)
          end
          parser.on('--aspect RATIO', PIXEL_ASPECTS, 'Pixel aspect: square or 8:7 (square)') do |pixel_aspect|
            options[:pixel_aspect] = pixel_aspect
          end
          parser.on('--crop-overscan', 'Show lines 8 to 231 only') { options[:crop_overscan] = true }
          parser.on('--config PATH', 'Key config file (~/.config/ruby-nes/config.yml)') do |path|
            options[:config_path] = path
          end
          parser.on('--no-audio', 'Play no sound; pace by the timer') { options[:audio] = false }
        end

        def self.headless_options(parser, options)
          parser.on('--headless', 'Run without a window or sound') { options[:headless] = true }
          parser.on('--frames COUNT', OptionParser::DecimalInteger, 'Frames to run') do |count|
            options[:frames] = at_least(FIRST_FRAME, count)
          end
          parser.on('--screenshot FRAME:PATH', SCREENSHOT, 'Write a frame as a PNG image') do |_argument, frame, path|
            add_screenshot(options[:screenshots], at_least(FIRST_FRAME, Integer(frame, DECIMAL)), path)
          end
          parser.on('--input SCRIPT', 'YAML input script: frame number to buttons held') do |path|
            options[:input_path] = path
          end
          parser.on('--wav PATH', 'Write the audio as a WAV file') { |path| options[:wav_path] = path }
        end

        # OptionParser puts the option's name in front of the message: "invalid argument: --frames 0 (at least 1)".
        def self.at_least(minimum, number)
          return number if number >= minimum

          raise OptionParser::InvalidArgument, "#{number} (at least #{minimum})"
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

        # The rate at which the run makes audio: the window plays it unless --no-audio, the headless run keeps it only
        # for --wav; nil when nobody would hear it, so the console mixes nothing (plan 24, decision 6).
        def audio_sample_rate
          heard = headless ? !wav_path.nil? : audio
          Audio::SAMPLE_RATE if heard
        end

        private_class_method(
          :parser,
          :window_options,
          :headless_options,
          :at_least,
          :add_screenshot,
          :ensure_one_rom,
          :ensure_screenshots_run
        )
      end
    end
  end
end
