# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      # The DMC, delta modulation channel (https://www.nesdev.org/wiki/APU_DMC), registers $4010-$4013 numbered 0-3:
      # `IL-- RRRR` (interrupt enable, loop, rate index), `-DDD DDDD` (direct load), the sample address and the sample
      # length. Its parts are the Sample (address and bytes-remaining counters), the MemoryReader (the sample buffer,
      # filled by DMA), the OutputUnit (the 7-bit level the mixer gets) and an InterruptFlag, the DMC_IRQ source. A
      # timer ticked every APU cycle clocks the output unit at the rate; $4015 clears the flag and starts or stops the
      # sample. Register effects are stamped with the CPU's access cycle (Cpu#access_cycle). The CPU and the bus are
      # given through writers, as the Console builds them after the APU. Hot path: the timer ticks every APU cycle.
      class Dmc
        # The registers, numbered from the channel's first address.
        CONTROL_REGISTER = 0
        DIRECT_LOAD_REGISTER = 1
        ADDRESS_REGISTER = 2
        LENGTH_REGISTER = 3
        # `IL-- RRRR`.
        INTERRUPT_ENABLE_FLAG = 0x80
        LOOP_FLAG = 0x40
        RATE_INDEX_MASK = 0x0F
        # The NTSC rates in CPU cycles, as the timer's reload values.
        RATES_IN_CPU_CYCLES = [428, 380, 340, 320, 286, 254, 226, 214, 190, 160, 142, 128, 106, 84, 72, 54].freeze
        TIMER_PERIODS = RATES_IN_CPU_CYCLES.map { |cpu_cycles| Timer.reload_for(cpu_cycles) }.freeze

        # One keyword per collaborator, so specs can stand in for each; the timer clocks this channel. $4010 is 0 at
        # power (https://www.nesdev.org/wiki/CPU_power_up_state): the first rate.
        # rubocop:disable-next Metrics/ParameterLists
        def initialize(cpu: nil, interrupt: InterruptFlag.new(source: Cpu::InterruptLines::DMC_IRQ, cpu:),
                       sample: Sample.new(interrupt:), reader: MemoryReader.new(sample:, cpu:),
                       output_unit: OutputUnit.new(reader:),
                       timer: Timer.new(sequencer: self, period: TIMER_PERIODS.first))
          @cpu = cpu
          @interrupt = interrupt
          @sample = sample
          @reader = reader
          @output_unit = output_unit
          @timer = timer
          @cycle = 0
        end

        def cpu=(cpu)
          @cpu = cpu
          @interrupt.cpu = cpu
          @reader.cpu = cpu
        end

        # The CPU bus, which the memory reader reads the sample from.
        def memory=(memory)
          @reader.memory = memory
        end

        # Register `register` (0-3) of the channel.
        def write(register, value)
          case register
          when CONTROL_REGISTER then write_control(value)
          when DIRECT_LOAD_REGISTER then @output_unit.direct_load(value)
          when ADDRESS_REGISTER then @sample.address_register = value
          else @sample.length_register = value
          end
        end

        # One APU cycle, on CPU cycle `cycle`.
        def tick_timer(cycle)
          @cycle = cycle
          @timer.tick
        end

        # The timer clocks the channel.
        def step
          @output_unit.clock(@cycle)
        end

        # A $4015 write on `cycle`, with its DMC bit as `enabled`: the interrupt flag clears, then the sample starts or
        # stops.
        def write_status(enabled, cycle)
          @interrupt.clear(cycle)
          if enabled
            @reader.start(cycle)
          else
            @reader.stop
          end
        end

        # $4015 bit 4: bytes remain.
        def active? = @reader.active?

        # $4015 bit 7.
        def interrupt? = @interrupt.flag?

        # 0-127, whether the channel plays or not.
        def output = @output_unit.output

        # "[$4011] &= 1" after reset (https://www.nesdev.org/wiki/CPU_power_up_state).
        def reset
          @output_unit.reset
        end

        private

        def write_control(value)
          @interrupt.change_inhibit((value & INTERRUPT_ENABLE_FLAG) == 0, @cpu.access_cycle) # glossary: flag-clear
          @sample.loop = (value & LOOP_FLAG) != 0 # glossary: flag-set
          @timer.period = TIMER_PERIODS[value & RATE_INDEX_MASK] # glossary: low-bits
        end
      end
    end
  end
end

require_relative 'dmc/sample'
require_relative 'dmc/memory_reader'
require_relative 'dmc/output_unit'
