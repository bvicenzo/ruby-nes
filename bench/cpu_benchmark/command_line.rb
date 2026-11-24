# frozen_string_literal: true

require 'json'

module CpuBenchmark
  # nestest has not been fetched (`rake test_roms:fetch`), so there is no workload to run.
  class MissingRom < Error; end

  # bench/cpu.rb: loads the variant asked for, checks that its trace still matches the whole of nestest.log (nestest's
  # result bytes alone let a broken CPU through: a variant that missed every branch target kept them at zero), then
  # measures the workload under the JIT this process runs with and prints the measurement as one JSON line for
  # `rake bench:cpu` and `rake bench:variants` to collect.
  class CommandLine
    NESTEST_FILES = [Nestest::ROM_PATH, Nestest::LOG_PATH].freeze

    def initialize(arguments, output: $stdout, requirement: TestRoms.requirement)
      @arguments = arguments
      @output = output
      @requirement = requirement
    end

    def run
      options = Options.parse(@arguments)
      variant_path = Variants.path(options.variant)
      unavailable_reason = @requirement.skip_reason(NESTEST_FILES)
      raise MissingRom, unavailable_reason if unavailable_reason

      require variant_path
      cartridge = Ruby::Nes::Cartridge::Loader.from_file(@requirement.path_of(Nestest::ROM_PATH))
      log_lines = Nestest::Log.lines(File.read(@requirement.path_of(Nestest::LOG_PATH)))
      ensure_trace_matches(cartridge, log_lines)
      workload = Workload.new(cartridge, steps_per_pass: log_lines.size)
      summary = session(options, workload).measure
      @output.puts(JSON.generate(Measurement.to_h(summary, variant: options.variant)))
    end

    private

    def ensure_trace_matches(cartridge, log_lines)
      divergence = Nestest::Runner.automation_mode(cartridge).first_divergence(log_lines)
      raise BrokenVariant, divergence.message if divergence
    end

    def session(options, workload)
      Session.new(
        workload:,
        cycles: options.cycles,
        warm_up_runs: options.warm_up_runs,
        measured_runs: options.measured_runs
      )
    end
  end
end
