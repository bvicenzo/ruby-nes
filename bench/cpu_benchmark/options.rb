# frozen_string_literal: true

require 'optparse'

module CpuBenchmark
  # The command line of bench/cpu.rb: which variant to load (none, `baseline`, by default) and the workload's size
  # (plan 10, decision 1: 10 million cycles per run, 2 warm-up runs, 5 measured runs).
  Options = Data.define(:variant, :cycles, :warm_up_runs, :measured_runs) do
    def self.parse(arguments)
      options = { variant: Variants::BASELINE, **CpuBenchmark::Options::WORKLOAD_DEFAULTS }
      parser(options).parse(arguments)
      new(**options)
    end

    def self.parser(options)
      OptionParser.new do |parser|
        parser.banner = 'Usage: ruby [--yjit | --zjit] bench/cpu.rb [options]'
        parser.on('--variant NAME', 'A file of bench/cpu_benchmark/variants') { |name| options[:variant] = name }
        parser.on('--cycles COUNT', Integer, 'Cycles per run') do |count|
          options[:cycles] = at_least(count, minimum: 1)
        end
        parser.on('--warm-up-runs COUNT', Integer, 'Untimed runs first') do |count|
          options[:warm_up_runs] = at_least(count, minimum: 0)
        end
        parser.on('--runs COUNT', Integer, 'Measured runs') do |count|
          options[:measured_runs] = at_least(count, minimum: 1)
        end
      end
    end
    private_class_method :parser

    # OptionParser puts the option's name in front of the message: "invalid argument: --runs 0 (at least 1)".
    def self.at_least(count, minimum:)
      return count if count >= minimum

      raise OptionParser::InvalidArgument, "#{count} (at least #{minimum})"
    end
    private_class_method :at_least
  end

  # The workload when no option overrides it; the rake tasks name it in the titles they write.
  Options::WORKLOAD_DEFAULTS = { cycles: 10_000_000, warm_up_runs: 2, measured_runs: 5 }.freeze
end
