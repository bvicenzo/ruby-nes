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
        # `LLLL LTTT`: the length table index (the length counter's) and the timer's high 3 bits.
        TIMER_HIGH_MASK = 0x07

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
          when TIMER_LOW_REGISTER then write_timer_low(value)
          else write_length_and_timer_high(value)
          end
        end

        # One APU cycle.
        def tick_timer
          @timer.tick
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
          @length_counter.halted = value.anybits?(LENGTH_COUNTER_HALT_FLAG)
          @envelope.write(value)
        end

        def write_timer_low(value)
          @timer.period = (@timer.period & ~Bits::BYTE_MASK) | value # glossary: place-bit-field
        end

        def write_length_and_timer_high(value)
          high = value & TIMER_HIGH_MASK # glossary: low-bits
          @timer.period = (high << Bits::BYTE_WIDTH) | (@timer.period & Bits::BYTE_MASK) # glossary: combine-bytes
          @length_counter.load(value)
          @sequencer.restart
          @envelope.restart
        end
      end
    end
  end
end
