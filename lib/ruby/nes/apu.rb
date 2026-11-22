# frozen_string_literal: true

module Ruby
  module Nes
    # The APU (Audio Processing Unit) of the 2A03 (https://www.nesdev.org/wiki/APU), the device in CpuBus's
    # `apu_registers:` slot: $4000-$4003 pulse 1, $4004-$4007 pulse 2, $4008-$400B triangle, $400C-$400F noise,
    # $4010-$4013 DMC, $4015 status and enable, $4017 the frame counter (its reads are the controller port's). A channel
    # register reaches its channel through a constant table indexed by address bits 4-2. $4015 reads `IF-D NT21`, the
    # DMC and frame interrupt flags, the DMC's bytes remaining and each length counter above 0, with bit 5 from the data
    # bus ("the last cycle that did not read $4015"); the bus does not store what this slot returns (plan 22, decision
    # 2). The other registers drive nothing. Its output is the Mixer's, on demand (plan 23, decision 8).
    #
    # Caught up like the PPU (plan 22, decision 3): `catch_up(cpu_cycle)` runs every CPU cycle before `cpu_cycle`, the
    # frame counter and the triangle timer on each, the pulse, noise and DMC timers on the even ones (the GET cycles,
    # decision 5). The console calls it after each step; a register access first catches up through the access cycle,
    # Cpu#access_cycle, past any DMC stall on the way, the CPU being this unit's clock as it is MMC1's. With an audio
    # resampler attached, each cycle caught up also hands it the mix of the five channels (plan 24). Reset writes $00
    # to $4015 and clears the frame interrupt flag, writes $4017's last value again (apu_reset's readme, plan 22
    # decision 4) and resets the triangle's phase and the DMC's level (https://www.nesdev.org/wiki/CPU_power_up_state).
    # Hot path: integers only, no allocation per cycle.
    class Apu
      # "2 CPU cycles = 1 APU cycle" (https://www.nesdev.org/wiki/APU_Frame_Counter).
      CPU_CYCLES_PER_APU_CYCLE = 2
      # $4000-$4013: four registers per channel, the channel in address bits 4-2, the register in bits 1-0.
      CHANNEL_REGISTERS_END = 0x4014
      CHANNEL_INDEX_MASK = 0x1C
      CHANNEL_INDEX_SHIFT = 2
      CHANNEL_REGISTER_MASK = 0x03
      STATUS = 0x4015
      FRAME_COUNTER = 0x4017
      # $4015: `IF-D NT21` read, `---D NT21` written.
      FIRST_PULSE_FLAG = 0x01
      SECOND_PULSE_FLAG = 0x02
      TRIANGLE_FLAG = 0x04
      NOISE_FLAG = 0x08
      DMC_FLAG = 0x10
      OPEN_BUS_FLAG = 0x20
      FRAME_INTERRUPT_FLAG = 0x40
      DMC_INTERRUPT_FLAG = 0x80

      # One keyword per collaborator, so specs can stand in for each; the frame counter clocks this APU's channels.
      # `resampler`, an Audio::Resampler, takes the mix of every CPU cycle; without one nothing is mixed (plan 24,
      # decision 6: the safe navigation skips evaluating `output`).
      # rubocop:disable-next Metrics/ParameterLists
      def initialize(cpu: nil, first_pulse: Pulse.new(negation: Sweep::ONES_COMPLEMENT),
                     second_pulse: Pulse.new(negation: Sweep::TWOS_COMPLEMENT), triangle: Triangle.new,
                     noise: Noise.new, dmc: Dmc.new(cpu:),
                     frame_interrupt: InterruptFlag.new(source: Cpu::InterruptLines::FRAME_IRQ, cpu:),
                     frame_counter: FrameCounter.new(listener: self, interrupt: frame_interrupt), resampler: nil)
        @cpu = cpu
        @first_pulse = first_pulse
        @second_pulse = second_pulse
        @triangle = triangle
        @noise = noise
        @dmc = dmc
        @channels = [first_pulse, second_pulse, triangle, noise, dmc].freeze
        @frame_interrupt = frame_interrupt
        @frame_counter = frame_counter
        @resampler = resampler
        @cycle = 0
      end

      # The CPU, the APU's clock, the IRQ line of its interrupt flags and what the DMC halts.
      def cpu=(cpu)
        @cpu = cpu
        @frame_interrupt.cpu = cpu
        @dmc.cpu = cpu
      end

      # The CPU bus, which the DMC reads its samples from.
      def memory=(memory)
        @dmc.memory = memory
      end

      def cpu_read(address, data_bus)
        return data_bus unless address == STATUS

        catch_up_to_access
        read_status(data_bus)
      end

      def cpu_write(address, value)
        catch_up_to_access
        if address < CHANNEL_REGISTERS_END
          channel = @channels[(address & CHANNEL_INDEX_MASK) >> CHANNEL_INDEX_SHIFT] # glossary: bit-field
          channel.write(address & CHANNEL_REGISTER_MASK, value) # glossary: low-bits
        elsif address == STATUS
          write_status(value, @cpu.access_cycle)
        elsif address == FRAME_COUNTER
          @frame_counter.write(value, @cpu.access_cycle)
        end
      end

      # Runs every CPU cycle before `cpu_cycle`.
      def catch_up(cpu_cycle)
        while @cycle < cpu_cycle
          @frame_counter.tick(@cycle)
          @triangle.tick_timer
          if @cycle.even?
            @first_pulse.tick_timer
            @second_pulse.tick_timer
            @noise.tick_timer
            @dmc.tick_timer(@cycle)
          end
          @resampler&.add(output)
          @cycle += 1
        end
      end

      # The frame counter's quarter frame: the envelopes and the triangle's linear counter.
      def quarter_frame
        @first_pulse.quarter_frame
        @second_pulse.quarter_frame
        @triangle.quarter_frame
        @noise.quarter_frame
      end

      # The frame counter's half frame: the length counters and the sweeps.
      def half_frame
        @first_pulse.half_frame
        @second_pulse.half_frame
        @triangle.half_frame
        @noise.half_frame
      end

      # 0.0-1.0, the mix of the five channels as they stand.
      def output
        Mixer.mix(@first_pulse.output, @second_pulse.output, @triangle.output, @noise.output, @dmc.output)
      end

      # "At power and reset, $4015 is cleared", "IRQ flag is clear", and "last value written to $4017 is written again"
      # (apu_reset's readme; plan 22, decision 4), on the cycle the APU stands at; then the triangle's phase and the
      # DMC's level (https://www.nesdev.org/wiki/CPU_power_up_state).
      def reset
        write_status(0, @cycle)
        @frame_interrupt.clear(@cycle)
        @frame_counter.reset(@cycle)
        @triangle.reset
        @dmc.reset
      end

      private

      # Catches up through the access cycle. A DMC fetch on the way halts the CPU and moves the access past the stall,
      # so the catch-up goes on until it reaches the CPU: the access sees the APU as it stands after the stall, on the
      # cycle it is stamped with (Known gaps: DMC DMA timing).
      def catch_up_to_access
        catch_up(@cpu.cycles) while @cycle < @cpu.cycles
      end

      # A $4015 write on `cycle`.
      def write_status(value, cycle)
        @first_pulse.enabled = value.anybits?(FIRST_PULSE_FLAG)
        @second_pulse.enabled = value.anybits?(SECOND_PULSE_FLAG)
        @triangle.enabled = value.anybits?(TRIANGLE_FLAG)
        @noise.enabled = value.anybits?(NOISE_FLAG)
        @dmc.write_status(value.anybits?(DMC_FLAG), cycle)
      end

      def read_status(data_bus)
        status = (data_bus & OPEN_BUS_FLAG) | channel_status # glossary: bitwise-and
        status |= FRAME_INTERRUPT_FLAG if @frame_interrupt.read(@cpu.access_cycle) # glossary: set-flag
        status |= DMC_INTERRUPT_FLAG if @dmc.interrupt? # glossary: set-flag
        status
      end

      # $4015 bits 4-0, `---D NT21`: the channels still sounding.
      def channel_status
        status = 0
        status |= FIRST_PULSE_FLAG if @first_pulse.active? # glossary: set-flag
        status |= SECOND_PULSE_FLAG if @second_pulse.active? # glossary: set-flag
        status |= TRIANGLE_FLAG if @triangle.active? # glossary: set-flag
        status |= NOISE_FLAG if @noise.active? # glossary: set-flag
        status |= DMC_FLAG if @dmc.active? # glossary: set-flag
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
require_relative 'apu/linear_counter'
require_relative 'apu/triangle_sequencer'
require_relative 'apu/triangle'
require_relative 'apu/noise_shift_register'
require_relative 'apu/noise'
require_relative 'apu/interrupt_flag'
require_relative 'apu/frame_counter'
require_relative 'apu/dmc'
require_relative 'apu/mixer'
