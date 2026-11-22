# frozen_string_literal: true

require 'optparse'

module FrameBenchmark
  # The command line's options. The defaults play Super Mario Bros. 3 into world 1-1 (plan 25, decision 2).
  Options = Data.define(:rom, :input, :warm_up_frames, :frames_per_run, :measured_runs) do
    def self.parse(arguments)
      options = FrameBenchmark::Options::DEFAULTS.dup
      parser(options).parse(arguments)
      new(**options)
    end

    def self.parser(options)
      OptionParser.new do |parser|
        parser.banner = 'Usage: ruby [--yjit | --zjit] bench/frame.rb [options]'
        parser.on('--rom PATH', 'The ROM to play') { |path| options[:rom] = path }
        parser.on('--input PATH', 'The input script (YAML)') { |path| options[:input] = path }
        parser.on('--warm-up-frames COUNT', Integer, 'Untimed frames first') do |count|
          options[:warm_up_frames] = at_least(count, minimum: 0, option: '--warm-up-frames')
        end
        parser.on('--frames COUNT', Integer, 'Frames per measured run') do |count|
          options[:frames_per_run] = at_least(count, minimum: 1, option: '--frames')
        end
        parser.on('--runs COUNT', Integer, 'Measured runs') do |count|
          options[:measured_runs] = at_least(count, minimum: 1, option: '--runs')
        end
      end
    end
    private_class_method :parser

    def self.at_least(count, minimum:, option:)
      return count if count >= minimum

      raise OptionParser::InvalidArgument, "#{option} #{count} (at least #{minimum})"
    end
    private_class_method :at_least
  end

  Options::DEFAULTS = {
    rom: File.expand_path('../../roms/smb3.nes', __dir__),
    input: File.expand_path('../../spec/fixtures/smb3_world_1_1.yml', __dir__),
    warm_up_frames: 1200,
    frames_per_run: 60,
    measured_runs: 5
  }.freeze
end
