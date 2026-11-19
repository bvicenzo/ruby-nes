# frozen_string_literal: true

module Ruby
  module Nes
    module Input
      # The two controller ports, the device in CpuBus's `controller_ports:` slot (plan 15, decision 1), which hands it
      # reads of $4016 and $4017 and writes to $4016 only. "$4016 reads only from controller port 1, and $4017 reads only
      # from controller port 2"; "both are polled from a write to $4016" (https://www.nesdev.org/wiki/Controller_reading,
      # https://www.nesdev.org/wiki/Standard_controller). "The controller ports ($4016, $4017) affect only bits 4-0", and
      # "Bits 7-5 repeat the corresponding bits from the previous read" (https://www.nesdev.org/wiki/Open_bus_behavior):
      # a standard controller drives D0, and on the NES-001 D4-D1 read "0 if not connected"
      # (https://www.nesdev.org/wiki/Controller_reading).
      class ControllerPorts
        FIRST_PORT = 0x4016
        # CpuBus hands cpu_read FIRST_PORT and SECOND_PORT only, so any address but FIRST_PORT is SECOND_PORT.
        SECOND_PORT = 0x4017
        # The bits the ports leave to the data bus.
        OPEN_BUS_BITS = 0xE0

        def initialize(first:, second:)
          @first = first
          @second = second
        end

        def cpu_read(address, data_bus)
          controller = address == FIRST_PORT ? @first : @second
          (data_bus & OPEN_BUS_BITS) | controller.read # glossary: bitwise-and, bitwise-or
        end

        # Only $4016 reaches here: one strobe for both ports.
        def cpu_write(_address, value)
          @first.strobe(value)
          @second.strobe(value)
        end
      end
    end
  end
end
