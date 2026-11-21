# frozen_string_literal: true

module Ruby
  module Nes
    # The APU (Audio Processing Unit) of the 2A03 (https://www.nesdev.org/wiki/APU), the device in CpuBus's
    # `apu_registers:` slot: $4000-$4003 pulse 1, $4004-$4007 pulse 2, $4008-$400B triangle, $400C-$400F noise, $4015
    # status and enable, $4017 the frame counter (its reads are the controller port's). $4015 reads `IF-D NT21`, the
    # frame interrupt flag and each channel's length counter above 0, with bit 5 from the data bus ("the last cycle that
    # did not read $4015"); the bus does not store what this slot returns (plan 22, decision 2). The other registers
    # drive nothing. Of the triangle and the noise only the length counters exist so far (decision 8); the rest, and
    # the DMC, come with plan 23.
    #
    # Caught up like the PPU (plan 22, decision 3): `catch_up(cpu_cycle)` runs every CPU cycle before `cpu_cycle`, the
    # frame counter on each and the pulse timers on the even ones (the GET cycles, decision 5). The console calls it
    # after each step; a register access first catches up through the access cycle, Cpu#access_cycle, the CPU being
    # this unit's clock as it is MMC1's. Reset clears $4015 and the frame interrupt flag and writes $4017's last value
    # again (apu_reset's readme, plan 22 decision 4). Hot path: integers only, no allocation per cycle.
    class Apu
      # $4000-$4003 and $4004-$4007, each pulse's four registers.
      FIRST_PULSE_END = 0x4004
      SECOND_PULSE_END = 0x4008
      TRIANGLE_END = 0x400C
      NOISE_END = 0x4010
      # Each channel's four registers.
      CHANNEL_REGISTER_MASK = 0x03
      STATUS = 0x4015
      FRAME_COUNTER = 0x4017
      # $4015: `IF-D NT21` read, `---D NT21` written.
      FIRST_PULSE_FLAG = 0x01
      SECOND_PULSE_FLAG = 0x02
      TRIANGLE_FLAG = 0x04
      NOISE_FLAG = 0x08
      OPEN_BUS_FLAG = 0x20
      FRAME_INTERRUPT_FLAG = 0x40

      # One keyword per collaborator, so specs can stand in for each; the frame counter clocks this APU's channels.
      # rubocop:disable-next Metrics/ParameterLists
      def initialize(cpu: nil, first_pulse: Pulse.new(negation: Sweep::ONES_COMPLEMENT),
                     second_pulse: Pulse.new(negation: Sweep::TWOS_COMPLEMENT), triangle: Triangle.new,
                     noise: Noise.new, frame_interrupt: FrameInterrupt.new(cpu:),
                     frame_counter: FrameCounter.new(listener: self, interrupt: frame_interrupt))
        @cpu = cpu
        @first_pulse = first_pulse
        @second_pulse = second_pulse
        @triangle = triangle
        @noise = noise
        @frame_interrupt = frame_interrupt
        @frame_counter = frame_counter
        @cycle = 0
      end

      # The CPU, the APU's clock and its frame interrupt's IRQ line; the Console builds it after the bus.
      def cpu=(cpu)
        @cpu = cpu
        @frame_interrupt.cpu = cpu
      end

      def cpu_read(address, data_bus)
        return data_bus unless address == STATUS

        catch_up(@cpu.cycles)
        read_status(data_bus)
      end

      def cpu_write(address, value)
        catch_up(@cpu.cycles)
        register = address & CHANNEL_REGISTER_MASK # glossary: low-bits
        if address < FIRST_PULSE_END
          @first_pulse.write(register, value)
        elsif address < SECOND_PULSE_END
          @second_pulse.write(register, value)
        elsif address < TRIANGLE_END
          @triangle.write(register, value)
        elsif address < NOISE_END
          @noise.write(register, value)
        elsif address == STATUS
          enable_channels(value)
        elsif address == FRAME_COUNTER
          @frame_counter.write(value, @cpu.access_cycle)
        end
      end

      # Runs every CPU cycle before `cpu_cycle`.
      def catch_up(cpu_cycle)
        while @cycle < cpu_cycle
          @frame_counter.tick(@cycle)
          if @cycle.even?
            @first_pulse.tick_timer
            @second_pulse.tick_timer
          end
          @cycle += 1
        end
      end

      # The frame counter's quarter frame: the envelopes.
      def quarter_frame
        @first_pulse.quarter_frame
        @second_pulse.quarter_frame
      end

      # The frame counter's half frame: the length counters and the sweeps.
      def half_frame
        @first_pulse.half_frame
        @second_pulse.half_frame
        @triangle.half_frame
        @noise.half_frame
      end

      # "At power and reset, $4015 is cleared", "IRQ flag is clear", and "last value written to $4017 is written again"
      # (apu_reset's readme; plan 22, decision 4), on the cycle the APU stands at.
      def reset
        enable_channels(0)
        @frame_interrupt.reset(@cycle)
        @frame_counter.reset(@cycle)
      end

      private

      def enable_channels(value)
        @first_pulse.enabled = value.anybits?(FIRST_PULSE_FLAG)
        @second_pulse.enabled = value.anybits?(SECOND_PULSE_FLAG)
        @triangle.enabled = value.anybits?(TRIANGLE_FLAG)
        @noise.enabled = value.anybits?(NOISE_FLAG)
      end

      def read_status(data_bus)
        status = data_bus & OPEN_BUS_FLAG # glossary: bitwise-and
        status |= FIRST_PULSE_FLAG if @first_pulse.active? # glossary: set-flag
        status |= SECOND_PULSE_FLAG if @second_pulse.active? # glossary: set-flag
        status |= TRIANGLE_FLAG if @triangle.active? # glossary: set-flag
        status |= NOISE_FLAG if @noise.active? # glossary: set-flag
        status |= FRAME_INTERRUPT_FLAG if @frame_interrupt.read(@cpu.access_cycle) # glossary: set-flag
        status
      end
    end
  end
end

require_relative 'apu/length_counter'
require_relative 'apu/envelope'
require_relative 'apu/timer'
require_relative 'apu/duty_sequencer'
require_relative 'apu/sweep'
require_relative 'apu/pulse'
require_relative 'apu/triangle'
require_relative 'apu/noise'
require_relative 'apu/frame_interrupt'
require_relative 'apu/frame_counter'
