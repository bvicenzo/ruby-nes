# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The triangle channel (https://www.nesdev.org/wiki/APU_Triangle), registers $4008-$400B numbered 0-3: `CRRR RRRR`
      # (the linear counter; C also halts the length counter), an unused one, `TTTT TTTT` and `LLLL LTTT` (timer, length
      # counter load, and the linear counter's reload flag). The timer ticks every CPU cycle and clocks this channel,
      # which steps the 32-step sequencer only while both the linear and the length counter are above 0. The output is
      # the sequencer's value, held while it is stopped; periods below 2 are played like any other (plan 23, decision
      # 4). Hot path: ticked every CPU cycle.
      class Triangle
        # The registers, numbered from the channel's first address.
        CONTROL_REGISTER = 0
        TIMER_LOW_REGISTER = 2
        LENGTH_REGISTER = 3
        # $4008 bit 7: the linear counter's control flag, which also halts the length counter.
        CONTROL_FLAG = 0x80

        # One keyword per collaborator, so specs can stand in for each; the timer clocks this channel.
        def initialize(length_counter: LengthCounter.new, linear_counter: LinearCounter.new,
                       sequencer: TriangleSequencer.new, timer: Timer.new(sequencer: self))
          @length_counter = length_counter
          @linear_counter = linear_counter
          @sequencer = sequencer
          @timer = timer
        end

        # Register `register` (0-3) of the channel.
        def write(register, value)
          case register
          when CONTROL_REGISTER then write_control(value)
          when TIMER_LOW_REGISTER then @timer.write_period_low(value)
          when LENGTH_REGISTER then write_length_and_timer_high(value)
          end
        end

        # One CPU cycle.
        def tick_timer
          @timer.tick
        end

        # The timer clocks the channel.
        def step
          @sequencer.step if sequencing?
        end

        # The ticks before the timer's next clock, NEVER while a counter at 0 stops the sequencer: its clocks then change
        # nothing, and the counters change only on frame counter steps and register writes (plan 29). Hot path: once
        # per run.
        def quiet_ticks
          return NEVER unless sequencing?

          @timer.ticks_before_next_clock
        end

        # `ticks` CPU cycles at once, for a run of quiet cycles: the timer clocks the sequencer on each reload, unless a
        # counter at 0 stops it, whose clocks would change nothing. A stopped triangle's period is often 0 (its value at
        # power), a clock every cycle.
        def skip(ticks)
          if sequencing?
            @timer.skip(ticks)
          else
            @timer.skip_without_clocking(ticks)
          end
        end

        # The ticks from one clock to the next, for a quiet run of the other units that steps the triangle clock by clock
        # (plan 33).
        def ticks_per_clock = @timer.ticks_per_clock

        # `ticks` CPU cycles at once whose clocks were already made one by one (`step`, plan 33): the timer ends where the
        # ticks leave it, and the sequencer is not clocked again.
        def skip_without_clocking(ticks)
          @timer.skip_without_clocking(ticks)
        end

        def quarter_frame
          @linear_counter.clock
        end

        def half_frame
          @length_counter.clock
        end

        def enabled=(enabled)
          @length_counter.enabled = enabled
        end

        def active? = @length_counter.active?

        # 0-15.
        def output = @sequencer.output

        # "Triangle phase … 0" after reset (https://www.nesdev.org/wiki/CPU_power_up_state).
        def reset
          @sequencer.reset
        end

        private

        # Both counters are above 0: the timer's clocks step the sequencer.
        def sequencing? = @linear_counter.active? && @length_counter.active?

        def write_control(value)
          @linear_counter.write(value)
          @length_counter.halted = (value & CONTROL_FLAG) != 0 # glossary: flag-set
        end

        def write_length_and_timer_high(value)
          @timer.write_period_high(value)
          @length_counter.load(value)
          @linear_counter.restart
        end
      end
    end
  end
end
