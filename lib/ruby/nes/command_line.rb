# frozen_string_literal: true

require_relative '../nes'
require_relative 'frontends/base'
require_relative 'frontends/driver'
require_relative 'frontends/input_script'
require_relative 'frontends/palette'
require_relative 'frontends/png'
require_relative 'frontends/headless'

module Ruby
  module Nes
    # `ruby-nes`, the command line (plan 16): loads a ROM and runs it in a frontend. Only the headless frontend exists
    # so far; the window arrives in plan 18. A headless run prints the frame count and the last frame's digest, so two
    # runs can be compared. Off the hot path.
    class CommandLine
      SUCCESS = 0
      FAILURE = 1
      WINDOW_MISSING = 'only the headless frontend exists so far (plan 18 adds a window): pass --headless'

      def initialize(arguments, output: $stdout, error_output: $stderr)
        @arguments = arguments
        @output = output
        @error_output = error_output
      end

      # The exit status: 0 when the run completes; 1, with the reason on the error output, otherwise.
      def run
        options = Options.parse(@arguments)
        return print_information(options.information) if options.information
        return fail_with(WINDOW_MISSING) unless options.headless

        run_headless(options)
        SUCCESS
      rescue OptionParser::ParseError => error
        fail_with("#{error.message}\n#{Options::USAGE}")
      rescue Error, SystemCallError => error
        fail_with(error.message)
      end

      private

      def run_headless(options)
        console = Console.new(Cartridge::Loader.from_file(options.rom_path))
        frontend = Frontends::Headless.new(
          frames: options.frames, input_script: input_script(options.input_path), screenshots: options.screenshots
        )
        Frontends::Driver.new(console:, frontend:).run
        @output.puts("#{frontend.digests.size} frames, last frame SHA-256 #{frontend.digests.last}")
      end

      def input_script(path)
        return Frontends::InputScript::EMPTY unless path

        Frontends::InputScript.parse(File.read(path))
      end

      def print_information(information)
        @output.puts(information)
        SUCCESS
      end

      def fail_with(message)
        @error_output.puts("ruby-nes: #{message}")
        FAILURE
      end
    end
  end
end

require_relative 'command_line/options'
