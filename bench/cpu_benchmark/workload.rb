# frozen_string_literal: true

module CpuBenchmark
  # The benchmark's CPU work: whole nestest passes in automation mode, each from a freshly powered-up console
  # (Nestest::Runner.automation_mode), so every pass starts from the same state. A pass is one instruction per line of
  # nestest.log; after the last one, `C66E RTS`, the CPU would run into garbage. The clock is read around each pass's
  # instructions only, so building the console (and whatever a variant converts while it does) is not timed.
  # nestest's result bytes are checked after each pass, so a variant that breaks them raises instead of being measured.
  class Workload
    MONOTONIC_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }

    def initialize(cartridge, steps_per_pass:, clock: MONOTONIC_CLOCK)
      @cartridge = cartridge
      @steps_per_pass = steps_per_pass
      @clock = clock
    end

    # Runs whole passes until at least `cycles` CPU cycles were emulated; returns them with the seconds their
    # instructions took. The reset that powers each console up is not counted.
    def run(cycles:)
      emulated_cycles = 0
      seconds = 0.0
      while emulated_cycles < cycles
        pass = run_pass
        emulated_cycles += pass.cycles
        seconds += pass.seconds
      end
      Sample.new(cycles: emulated_cycles, seconds:)
    end

    private

    def run_pass
      runner = Nestest::Runner.automation_mode(@cartridge)
      started_at = @clock.call
      pass_cycles = run_steps(runner.cpu)
      pass = Sample.new(cycles: pass_cycles, seconds: @clock.call - started_at)
      ensure_passed(runner)
      pass
    end

    # A `while` loop rather than `Integer#times`: no block call per instruction in the code being timed.
    def run_steps(cpu)
      pass_cycles = 0
      steps = 0
      while steps < @steps_per_pass
        pass_cycles += cpu.step
        steps += 1
      end
      pass_cycles
    end

    def ensure_passed(runner)
      official_result = runner.official_result
      unofficial_result = runner.unofficial_result
      return if official_result.zero? && unofficial_result.zero?

      failure_message = format(
        'nestest failed after a pass: $0002 = $%<official_result>02X, $0003 = $%<unofficial_result>02X',
        official_result:,
        unofficial_result:
      )
      raise BrokenVariant, failure_message
    end
  end
end
