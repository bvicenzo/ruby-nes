# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The channels that can change within a few cycles (plan 33, decision 1): the triangle, whose timer is clocked
      # every CPU cycle down to a period of 0 (https://www.nesdev.org/wiki/APU_Triangle), the way games silence it, and
      # the noise, whose timer is clocked on the get cycles down to 4 CPU cycles a clock
      # (https://www.nesdev.org/wiki/APU_Noise). They do not cut the APU's runs of quiet cycles: through a run, in which
      # the slow units (the frame counter, the pulses and the DMC) stand still, they go clock by clock.
      #
      # A stopped triangle and a silent noise (`quiet_ticks` NEVER) skip the run as before. A sequencing triangle clocks
      # `quiet_ticks` cycles from the run's start and every `ticks_per_clock` cycles after; a sounding noise on the get
      # cycle of its `quiet_ticks`-th tick and every `ticks_per_clock` get cycles after. Each clock inside the run steps
      # its channel, in cycle order, both on the same cycle; a clock on the run's end is left to the next run. Then each
      # moves its timer on through the run without clocking. With a resampler, the run is handed as parts: the mix of the
      # slow channels' outputs (given, read once per run by the APU) with the fast ones' from the run's start, and anew
      # from each clock's cycle on, a clock on the run's first cycle leaving no part before it (a part of 1 cycle is the
      # resampler's business, plan 33 decision 2): the levels cycle by cycle would give. Hot path: once per run, a loop per clock.
      class FastChannels
        # An output of 0: a slow channel's when there is no resampler to mix it for, and every channel's before a run.
        SILENT = 0

        # `resampler`, an Audio::Resampler, takes the mix; without one nothing is mixed.
        def initialize(triangle:, noise:, resampler: nil)
          @triangle = triangle
          @noise = noise
          @resampler = resampler
          @first_pulse_output = @second_pulse_output = @dmc_output = @triangle_output = @noise_output = SILENT
          @triangle_clock = @triangle_clock_interval = @noise_clock = @noise_clock_interval = NEVER
        end

        # Runs CPU cycles `cycle` to `cycle` + `cycles` − 1, the slow channels' outputs standing at `first_pulse`,
        # `second_pulse` and `dmc`.
        def run(cycle, cycles, first_pulse = SILENT, second_pulse = SILENT, dmc = SILENT)
          @first_pulse_output = first_pulse
          @second_pulse_output = second_pulse
          @dmc_output = dmc
          timer_ticks = GetCycles.count(cycle, cycles)
          triangle_ticks = @triangle.quiet_ticks
          noise_ticks = @noise.quiet_ticks
          take_outputs if @resampler
          if triangle_ticks == NEVER && noise_ticks == NEVER
            hand_mix(cycles)
          else
            schedule_triangle(cycle, triangle_ticks)
            schedule_noise(cycle, noise_ticks)
            clock(cycle, cycle + cycles)
          end
          move_timers_through(triangle_ticks, noise_ticks, cycles, timer_ticks)
        end

        private

        def take_outputs
          @triangle_output = @triangle.output
          @noise_output = @noise.output
        end

        # The triangle's first clock, `ticks` cycles from `cycle`, and the cycles between its clocks.
        def schedule_triangle(cycle, ticks)
          @triangle_clock = ticks == NEVER ? NEVER : cycle + ticks
          @triangle_clock_interval = ticks == NEVER ? NEVER : @triangle.ticks_per_clock
        end

        # The noise's first clock, on the get cycle of its tick number `ticks` from `cycle`, and the cycles between its
        # clocks, two a tick.
        def schedule_noise(cycle, ticks)
          @noise_clock = ticks == NEVER ? NEVER : GetCycles.cycle_of_tick(cycle, ticks)
          @noise_clock_interval = ticks == NEVER ? NEVER : @noise.ticks_per_clock * CPU_CYCLES_PER_APU_CYCLE
        end

        # The clocks before `end_cycle`, in cycle order, each part of the run handed at its level; a clock on the run's
        # first cycle leaves no part before it.
        def clock(start_cycle, end_cycle)
          part_start = start_cycle
          while (clock_cycle = [@triangle_clock, @noise_clock].min) < end_cycle
            hand_mix(clock_cycle - part_start) if clock_cycle > part_start
            part_start = clock_cycle
            clock_triangle if clock_cycle == @triangle_clock
            clock_noise if clock_cycle == @noise_clock
          end
          hand_mix(end_cycle - part_start)
        end

        def clock_triangle
          @triangle.step
          @triangle_output = @triangle.output if @resampler
          @triangle_clock += @triangle_clock_interval
        end

        def clock_noise
          @noise.step
          @noise_output = @noise.output if @resampler
          @noise_clock += @noise_clock_interval
        end

        # `cycles` cycles at the mix as it stands, to the resampler.
        def hand_mix(cycles)
          @resampler&.add_run(
            Mixer.mix(@first_pulse_output, @second_pulse_output, @triangle_output, @noise_output, @dmc_output), cycles
          )
        end

        # Each channel's timer through the run: without clocking where its clocks were made, its own skip otherwise.
        def move_timers_through(triangle_ticks, noise_ticks, cycles, timer_ticks)
          if triangle_ticks == NEVER
            @triangle.skip(cycles)
          else
            @triangle.skip_without_clocking(cycles)
          end
          if noise_ticks == NEVER
            @noise.skip(timer_ticks)
          else
            @noise.skip_without_clocking(timer_ticks)
          end
        end
      end
    end
  end
end
