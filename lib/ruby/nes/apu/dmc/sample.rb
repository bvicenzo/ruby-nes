# frozen_string_literal: true

module Ruby
  module Nes
    class Apu
      class Dmc
        # The DMC sample's address and bytes-remaining counters (https://www.nesdev.org/wiki/APU_DMC), reloaded from the
        # $4012 and $4013 values when the sample restarts, so writing those registers leaves a playing sample alone.
        # Each byte read moves the address on, from $FFFF around to $8000, and counts the byte; after the last one the
        # loop flag restarts the sample, otherwise the sample-end interrupt is triggered. It starts with no bytes
        # remaining ($4013 is 0 at power, https://www.nesdev.org/wiki/CPU_power_up_state).
        class Sample
          # "Sample address = $C000 + (A * 64)".
          ADDRESS_BASE = 0xC000
          ADDRESS_STEP = 64
          # "Sample length = (L * 16) + 1 bytes".
          LENGTH_STEP = 16
          # "If it exceeds $FFFF, it's wrapped around $8000".
          LAST_ADDRESS = 0xFFFF
          WRAPPED_ADDRESS = 0x8000

          attr_reader :address, :bytes_remaining
          attr_writer :loop

          def initialize(interrupt:)
            @interrupt = interrupt
            @start_address = ADDRESS_BASE
            @length = 1
            @address = ADDRESS_BASE
            @bytes_remaining = 0
            @loop = false
          end

          # $4012.
          def address_register=(value)
            @start_address = ADDRESS_BASE + (value * ADDRESS_STEP)
          end

          # $4013.
          def length_register=(value)
            @length = (value * LENGTH_STEP) + 1
          end

          def restart
            @address = @start_address
            @bytes_remaining = @length
          end

          # The byte at `address` was read on `cycle`.
          def advance(cycle)
            @address = @address == LAST_ADDRESS ? WRAPPED_ADDRESS : @address + 1
            @bytes_remaining -= 1
            return unless @bytes_remaining.zero?

            if @loop
              restart
            else
              @interrupt.trigger(cycle)
            end
          end

          # $4015 with the DMC bit clear.
          def stop
            @bytes_remaining = 0
          end

          def active? = !@bytes_remaining.zero?
        end
      end
    end
  end
end
