# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The noise channel (https://www.nesdev.org/wiki/APU_Noise), registers $400C-$400F numbered 0-3: `--LC VVVV`
      # (envelope, length counter halt), an unused one, `M--- PPPP` (periodic mode, period index) and `LLLL L---`
      # (length counter load, envelope restart). A timer, ticked every APU cycle, clocks a NoiseShiftRegister; the
      # envelope and the length counter are the pulse's. The output is 0 while the shift register mutes the channel or
      # the length counter is 0, the envelope's volume otherwise. Hot path: the timer ticks every APU cycle.
      class Noise
        # The registers, numbered from the channel's first address.
        CONTROL_REGISTER = 0
        PERIOD_REGISTER = 2
        LENGTH_REGISTER = 3
        LENGTH_COUNTER_HALT_FLAG = 0x20
        # `M--- PPPP`.
        PERIODIC_FLAG = 0x80
        PERIOD_INDEX_MASK = 0x0F
        # The NTSC periods, "CPU cycles between shift register clocks", as the timer's reload values.
        PERIODS_IN_CPU_CYCLES = [4, 8, 16, 32, 64, 96, 128, 160, 202, 254, 380, 508, 762, 1016, 2034, 4068].freeze
        TIMER_PERIODS = PERIODS_IN_CPU_CYCLES.map { |cpu_cycles| Timer.reload_for(cpu_cycles) }.freeze

        # One keyword per collaborator, so specs can stand in for each; the timer clocks the shift register. $400E is 0
        # at power (https://www.nesdev.org/wiki/CPU_power_up_state): the first period.
        def initialize(envelope: Envelope.new, length_counter: LengthCounter.new,
                       shift_register: NoiseShiftRegister.new,
                       timer: Timer.new(sequencer: shift_register, period: TIMER_PERIODS.first))
          @envelope = envelope
          @length_counter = length_counter
          @shift_register = shift_register
          @timer = timer
        end

        # Register `register` (0-3) of the channel.
        def write(register, value)
          case register
          when CONTROL_REGISTER then write_control(value)
          when PERIOD_REGISTER then write_period(value)
          when LENGTH_REGISTER then write_length(value)
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
        end

        def enabled=(enabled)
          @length_counter.enabled = enabled
        end

        def active? = @length_counter.active?

        # 0-15.
        def output
          return 0 if @shift_register.muting? || !@length_counter.active?

          @envelope.volume
        end

        private

        def write_control(value)
          @envelope.write(value)
          @length_counter.halted = value.anybits?(LENGTH_COUNTER_HALT_FLAG)
        end

        def write_period(value)
          @shift_register.periodic = value.anybits?(PERIODIC_FLAG)
          @timer.period = TIMER_PERIODS[value & PERIOD_INDEX_MASK] # glossary: low-bits
        end

        def write_length(value)
          @length_counter.load(value)
          @envelope.restart
        end
      end
    end
  end
end
