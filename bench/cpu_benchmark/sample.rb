# frozen_string_literal: true

module CpuBenchmark
  # One timed run: the CPU cycles it emulated and the wall-clock seconds it took.
  Sample = Data.define(:cycles, :seconds)

  # Reopened rather than given a block: constants in a Data.define block resolve in the enclosing module.
  class Sample
    CYCLES_PER_MEGAHERTZ = 1_000_000.0

    def megahertz = cycles / seconds / CYCLES_PER_MEGAHERTZ
  end
end
