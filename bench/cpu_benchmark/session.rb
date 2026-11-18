# frozen_string_literal: true

module CpuBenchmark
  # One configuration's measurement: warm-up runs first, discarded, so the JIT compiles the hot methods; then the
  # measured runs, each timed by the workload and summarised (plan 10, decision 1).
  class Session
    def initialize(workload:, cycles:, warm_up_runs:, measured_runs:)
      @workload = workload
      @cycles = cycles
      @warm_up_runs = warm_up_runs
      @measured_runs = measured_runs
    end

    def measure
      @warm_up_runs.times { @workload.run(cycles: @cycles) }
      samples = Array.new(@measured_runs) { @workload.run(cycles: @cycles) }
      Summary.new(samples)
    end
  end
end
