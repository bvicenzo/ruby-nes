# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # A channel's timer (https://www.nesdev.org/wiki/APU_Pulse): a divider counting t, t-1, ..., 0, t, ..., that
      # clocks the channel's sequencer (anything that answers `step`) on the transition back to t. Its period starts at
      # 0 (https://www.nesdev.org/wiki/CPU_power_up_state). The pulse and triangle channels write it through two
      # registers, `TTTT TTTT` and `LLLL LTTT` (https://www.nesdev.org/wiki/APU). Hot path: ticked every APU cycle
      # (every CPU cycle for the triangle).
      class Timer
        # `LLLL LTTT`: the period's high 3 bits.
        PERIOD_HIGH_MASK = 0x07

        attr_accessor :period

        # The reload value of a timer ticked every APU cycle for a period of `cpu_cycles`, as the noise and DMC tables
        # give it: those timers are clocked "only on every second CPU cycle" (https://www.nesdev.org/wiki/APU) and count
        # their reload value down to 0.
        def self.reload_for(cpu_cycles) = (cpu_cycles / CPU_CYCLES_PER_APU_CYCLE) - 1

        def initialize(sequencer:, period: 0)
          @sequencer = sequencer
          @period = period
          @counter = 0
        end

        # The channel's third register: the period's low 8 bits.
        def write_period_low(value)
          @period = (@period & ~Bits::BYTE_MASK) | value # glossary: place-bit-field
        end

        # The channel's fourth register: its bits 2-0 are the period's high 3 bits.
        def write_period_high(value)
          high = value & PERIOD_HIGH_MASK # glossary: low-bits
          @period = (high << Bits::BYTE_WIDTH) | (@period & Bits::BYTE_MASK) # glossary: combine-bytes
        end

        # The ticks before the next clock: the tick that finds the counter at 0. A run of quiet cycles goes on until a
        # channel's next clock (plan 29).
        def ticks_before_next_clock = @counter

        # The ticks before the one on which clock number `clocks` (1 is the next) comes: the tick that finds the counter
        # at 0, then one every period + 1 ticks. The DMC's next fetch is on such a clock (plan 29).
        def ticks_before_clock(clocks)
          @counter + ((clocks - 1) * (@period + 1))
        end

        # `ticks` ticks at once, for a run of quiet cycles (plan 29): the sequencer is clocked on each reload, as the
        # ticks one by one would. Hot path: once per run, a loop per clock.
        def skip(ticks)
          while ticks > @counter
            ticks -= @counter + 1
            @counter = @period
            @sequencer.step
          end
          @counter -= ticks
        end

        # `ticks` ticks at once for a sequencer whose clocks would change nothing (a stopped triangle, plan 29): the
        # counter ends where the ticks would leave it, reloads included, without a call per clock.
        def skip_without_clocking(ticks)
          if ticks <= @counter
            @counter -= ticks
          else
            ticks_after_reload = ticks - @counter - 1
            @counter = @period - (ticks_after_reload % (@period + 1))
          end
        end

        def tick
          if @counter.zero?
            @counter = @period
            @sequencer.step
          else
            @counter -= 1
          end
        end
      end
    end
  end
end
