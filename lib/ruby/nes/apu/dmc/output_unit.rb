# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      class Dmc
        # The DMC's output unit (https://www.nesdev.org/wiki/APU_DMC): an 8-bit shift register whose bit 0, on each
        # timer clock, raises the 7-bit output level by 2 (below 126) or lowers it by 2 (above 1), then shifts right.
        # After eight clocks a new output cycle takes the memory reader's byte; with none it stays silent for eight
        # clocks, the level held. $4011 loads the level directly, and reset keeps only its bit 0 ("[$4011] &= 1",
        # https://www.nesdev.org/wiki/CPU_power_up_state). The level reaches the mixer whether the channel plays or not.
        # No page gives its state at power: by convention it starts silent, eight clocks from its first byte (plan 23,
        # decision 9). Hot path: clocked by the DMC timer.
        class OutputUnit
          LOWEST_BIT = 0x01
          # The level moves by 2 within 0-127: up while below 126, down while above 1.
          LEVEL_STEP = 2
          HIGHEST_RAISABLE_LEVEL = 125
          LOWEST_LOWERABLE_LEVEL = 2
          # $4011 `-DDD DDDD`.
          LEVEL_MASK = 0x7F
          # "[$4011] &= 1" after reset.
          RESET_LEVEL_MASK = 0x01

          def initialize(reader:)
            @reader = reader
            @level = 0
            @shift_register = 0
            @bits_remaining = Bits::BYTE_WIDTH
            @silent = true
          end

          # A timer clock on CPU cycle `cycle`.
          def clock(cycle)
            change_level unless @silent
            @shift_register >>= 1 # glossary: shift-right
            @bits_remaining -= 1
            start_output_cycle(cycle) if @bits_remaining.zero?
          end

          # $4011.
          def direct_load(value)
            @level = value & LEVEL_MASK # glossary: low-bits
          end

          def reset
            @level = Bits.low_bits(@level, RESET_LEVEL_MASK)
          end

          # 0-127.
          def output = @level

          private

          def change_level
            if (@shift_register & LOWEST_BIT) != 0 # glossary: flag-set
              @level += LEVEL_STEP if @level <= HIGHEST_RAISABLE_LEVEL
            elsif @level >= LOWEST_LOWERABLE_LEVEL
              @level -= LEVEL_STEP
            end
          end

          def start_output_cycle(cycle)
            @bits_remaining = Bits::BYTE_WIDTH
            byte = @reader.take_sample(cycle)
            @silent = byte.nil?
            @shift_register = byte unless @silent
          end
        end
      end
    end
  end
end
