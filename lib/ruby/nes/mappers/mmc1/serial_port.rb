# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      class Mmc1 < Base
        # The MMC1's serial load port (https://www.nesdev.org/wiki/MMC1), which knows nothing of the registers it
        # feeds. "On the first four writes, the MMC1 shifts bit 0 into a shift register. On the fifth write, the MMC1
        # copies bit 0 and the shift register contents into an internal register": #shift hands that 5-bit value back
        # on the fifth write, the first write's bit in bit 0, and "After the fifth write, the shift register is cleared
        # automatically". A write with bit 7 set "clears the shift register to its initial state" (#reset).
        #
        # "When the serial port is written to on consecutive cycles, it ignores every write after the first", which
        # read-modify-write instructions do; "the bit 7 reset is never ignored". A write less than 2 cycles after the
        # previous one is ignored, and every write, ignored or reset, becomes the previous one (plan 20, decision 2):
        # both writes of a read-modify-write instruction see the same Cpu#cycles, since a step charges its cycles
        # first. Mesen2's MMC1.h uses the same threshold.
        class SerialPort
          # Cycles that must separate a write from the previous one for the port to take it.
          MINIMUM_WRITE_GAP = 2
          # Before any write, the first one is never consecutive, even at cycle 0.
          NO_PREVIOUS_WRITE = -MINIMUM_WRITE_GAP
          # The data bit of every write.
          DATA_BIT = 0x01
          # The bit of the loaded value each accepted write fills, first write first.
          VALUE_BITS = [0x01, 0x02, 0x04, 0x08, 0x10].freeze

          def initialize
            @previous_write_cycle = NO_PREVIOUS_WRITE
            clear
          end

          # A write with bit 7 clear on `cycle`: nil, or the 5-bit value on the fifth accepted write.
          def shift(value, cycle)
            gap = cycle - @previous_write_cycle
            @previous_write_cycle = cycle
            return if gap < MINIMUM_WRITE_GAP

            @value = Bits.set_flag(@value, VALUE_BITS[@writes]) if (value & DATA_BIT) != 0 # glossary: flag-set
            @writes += 1
            return if @writes < VALUE_BITS.size

            loaded = @value
            clear
            loaded
          end

          # A write with bit 7 set on `cycle`: never ignored, and the previous write for the next one.
          def reset(cycle)
            @previous_write_cycle = cycle
            clear
          end

          private

          def clear
            @value = 0
            @writes = 0
          end
        end
      end
    end
  end
end
