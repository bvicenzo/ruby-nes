# frozen_string_literal: true

module Ruby
  module Nes
    class Console
      # The device in CpuBus's `ppu_registers:` slot (plan 12, decision 1): before handing an access to the PPU, it
      # catches the PPU up to the start of the instruction's last cycle. Cpu#step charges the base cycles before running
      # the instruction, so `cpu.cycles` is then the cycle it ends on, and every non-read-modify-write instruction makes
      # its data access on its last cycle (https://www.nesdev.org/6502_cpu.txt); read-modify-write instructions on PPU
      # registers are approximated. The Console gives the CPU through the writer, since it builds the CPU after the bus.
      # The cartridge board asks for the same catch-up before each register write (plan 21, decision 6).
      class PpuRegisterSync
        attr_writer :cpu

        def initialize(ppu:, cpu: nil)
          @ppu = ppu
          @cpu = cpu
        end

        def cpu_read(address, data_bus)
          catch_up
          @ppu.cpu_read(address, data_bus)
        end

        def cpu_write(address, value)
          catch_up
          @ppu.cpu_write(address, value)
        end

        # Catches the PPU up to the start of the cycle the instruction's access falls on, Cpu#access_cycle.
        def catch_up
          @ppu.catch_up(@cpu.access_cycle)
        end
      end
    end
  end
end
