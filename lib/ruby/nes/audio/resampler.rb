# frozen_string_literal: true

module Ruby
  module Nes
    module Audio
      # A box resampler (plan 24, decision 4): the APU adds its level every CPU cycle, and at the end of each output
      # period the mean of that period's levels goes to the output. The period is an exact fraction of cycles: each
      # cycle adds the output rate × the input rate's denominator to a phase, and a sample is due each time the phase
      # reaches the input rate's numerator. Hot path (once per CPU cycle with audio on): integers and floats only.
      class Resampler
        # The CPU clock: the master clock, "236.25 MHz ÷ 11 by definition", ÷ 12
        # (https://www.nesdev.org/wiki/Cycle_reference_chart), so 945 000 000 / 528 Hz.
        CPU_CLOCK_RATE = Rational(945_000_000, 4 * 11 * 12)

        # `input_rate` (levels per second) is an Integer or a Rational.
        def initialize(output_rate:, output:, input_rate: CPU_CLOCK_RATE)
          @output = output
          @phase_step = output_rate * input_rate.denominator
          @phase_per_sample = input_rate.numerator
          @phase = 0
          @sum = 0.0
          @count = 0
        end

        def add(level)
          @sum += level
          @count += 1
          @phase += @phase_step
          return if @phase < @phase_per_sample

          @phase -= @phase_per_sample
          @output.push(@sum / @count)
          @sum = 0.0
          @count = 0
        end

        # `level` for `cycles` cycles, a run of quiet cycles (plan 29): the samples are those of as many #add calls. The
        # run is split where samples are due, found from the integer phase; within each part the level is still added
        # once per cycle, since adding it n times and adding n × it can differ in the float sum's last bits. Hot path:
        # once per run, a loop of float additions per cycle.
        def add_run(level, cycles)
          until cycles.zero?
            # At least one cycle: with an output rate above the input rate the phase can stand past a sample, and #add
            # then pushes one per cycle.
            part = (@phase_per_sample - @phase).ceildiv(@phase_step).clamp(1, cycles)
            add_level(level, part)
            cycles -= part
            next if @phase < @phase_per_sample

            @phase -= @phase_per_sample
            @output.push(@sum / @count)
            @sum = 0.0
            @count = 0
          end
        end

        private

        # `level` for `cycles` cycles within one output period.
        def add_level(level, cycles)
          sum = @sum
          remaining = cycles
          until remaining.zero?
            sum += level
            remaining -= 1
          end
          @sum = sum
          @count += cycles
          @phase += cycles * @phase_step
        end
      end
    end
  end
end
