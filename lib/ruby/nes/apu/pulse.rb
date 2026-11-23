# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # A pulse channel (https://www.nesdev.org/wiki/APU_Pulse): a timer clocking an 8-step duty sequencer, an envelope,
      # a sweep unit and a length counter, written through four registers numbered 0-3 from its first address. Pulse 1
      # and pulse 2 differ only in how the sweep negates (`negation`, Sweep::ONES_COMPLEMENT or ::TWOS_COMPLEMENT). The
      # output is 0-15: 0 when the length counter is 0, the sweep mutes the channel or the sequencer outputs 0; the
      # envelope's volume otherwise. Hot path: the timer ticks every APU cycle and register writes are bus accesses.
      class Pulse
        # The registers, numbered from the channel's first address.
        CONTROL_REGISTER = 0
        SWEEP_REGISTER = 1
        TIMER_LOW_REGISTER = 2
        # `DDLC VVVV`.
        DUTY_MASK = 0xC0
        DUTY_SHIFT = 6
        LENGTH_COUNTER_HALT_FLAG = 0x20

        # One keyword per collaborator, so specs can stand in for each; the sweep adjusts the channel's own timer.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(negation:, sequencer: DutySequencer.new, timer: Timer.new(sequencer:), envelope: Envelope.new,
                       length_counter: LengthCounter.new, sweep: Sweep.new(timer:, negation:))
          @timer = timer
          @sequencer = sequencer
          @envelope = envelope
          @length_counter = length_counter
          @sweep = sweep
        end

        # Register `register` (0-3) of the channel.
        def write(register, value)
          case register
          when CONTROL_REGISTER then write_control(value)
          when SWEEP_REGISTER then @sweep.write(value)
          when TIMER_LOW_REGISTER then @timer.write_period_low(value)
          else write_length_and_timer_high(value)
          end
        end

        # One APU cycle.
        def tick_timer
          @timer.tick
        end

        # The ticks before the timer's next clock, NEVER while the channel is muted: its output stays 0 whatever the
        # sequencer does, and the length counter, the sweep and the envelope change only on frame counter steps and
        # register writes (plan 29). Hot path: once per run.
        def quiet_ticks
          return NEVER if !@length_counter.active? || @sweep.muting? || @envelope.volume.zero?

          @timer.ticks_before_next_clock
        end

        # `ticks` APU cycles at once, for a run of quiet cycles.
        def skip(ticks)
          @timer.skip(ticks)
        end

        def quarter_frame
          @envelope.clock
        end

        def half_frame
          @length_counter.clock
          @sweep.clock
        end

        # Bit 0 or 1 of a $4015 write.
        def enabled=(enabled)
          @length_counter.enabled = enabled
        end

        def active? = @length_counter.active?

        def output
          return 0 if !@length_counter.active? || @sweep.muting? || @sequencer.output.zero?

          @envelope.volume
        end

        private

        def write_control(value)
          @sequencer.duty = (value & DUTY_MASK) >> DUTY_SHIFT # glossary: bit-field
          @length_counter.halted = (value & LENGTH_COUNTER_HALT_FLAG) != 0 # glossary: flag-set
          @envelope.write(value)
        end

        # `LLLL LTTT`: the length table index (the length counter's) and the timer's high 3 bits.
        def write_length_and_timer_high(value)
          @timer.write_period_high(value)
          @length_counter.load(value)
          @sequencer.restart
          @envelope.restart
        end
      end
    end
  end
end
