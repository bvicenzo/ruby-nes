# frozen_string_literal: true

module Ruby
  module Nes
    class CpuBus
      # The device in a CPU bus slot nothing is plugged into yet: it never drives the data bus, so a read returns what
      # was left on it (open bus, https://www.nesdev.org/wiki/Open_bus_behavior), and a write goes nowhere. Also the
      # shape of the device interface every slot expects.
      module Disconnected
        def self.cpu_read(_address, data_bus) = data_bus

        def self.cpu_write(_address, _value) = nil
      end
    end
  end
end
