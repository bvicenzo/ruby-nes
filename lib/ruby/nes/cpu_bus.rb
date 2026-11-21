# frozen_string_literal: true

module Ruby
  module Nes
    # The CPU's view of the 64 KiB address space (https://www.nesdev.org/wiki/CPU_memory_map): the 2 KiB of internal
    # RAM and three mirrors, the PPU registers mirrored every 8 bytes, the APU registers, the controller ports, the
    # disabled test range, and the cartridge. Devices plug into slots and answer `cpu_read(address, data_bus)` with the
    # byte left on the data bus, and `cpu_write(address, value)`; an empty slot is Disconnected.
    #
    # Open bus (https://www.nesdev.org/wiki/Open_bus_behavior): "reading open bus repeats the last value that was read
    # from the bus before this read". Every read stores its result as the data bus value, and a device that does not
    # drive the bus returns that value untouched. Writes do not change it: the page documents reads only. The APU slot
    # is the exception: its registers are internal to the 2A03, so what it returns is not stored (plan 22, decision 2).
    #
    # The bus owns the OAM DMA unit (plan 11, decision 2): a write to OAMDMA ($4014) starts it instead of reaching the
    # APU slot, and the stall it costs the CPU comes back through #take_stall_cycles, which Cpu#step adds.
    #
    # The 2A03 decodes $4000-$4017 itself (plan 15, decision 1): reads of $4016 and $4017 and writes to $4016 reach the
    # controller ports; the rest of the range, writes to $4017 (the APU frame counter) included, reaches the APU.
    class CpuBus
      RAM_SIZE = 0x0800
      # $0800-$1FFF repeat the 2 KiB of RAM.
      RAM_MIRROR_MASK = 0x07FF
      PPU_REGISTERS_START = 0x2000
      # $2008-$3FFF repeat $2000-$2007 every 8 bytes.
      PPU_REGISTER_MIRROR_MASK = 0x2007
      APU_REGISTERS_START = 0x4000
      # "OAM DMA copies 256 bytes from a CPU page to PPU OAM" (https://www.nesdev.org/wiki/DMA).
      OAMDMA = 0x4014
      # "$4016 reads only from controller port 1, and $4017 reads only from controller port 2"
      # (https://www.nesdev.org/wiki/Controller_reading); "both are polled from a write to $4016"
      # (https://www.nesdev.org/wiki/Standard_controller).
      CONTROLLER_PORTS_START = 0x4016
      CONTROLLER_STROBE = 0x4016
      # "APU and I/O functionality that is normally disabled": nothing answers $4018-$401F.
      TEST_MODE_START = 0x4018
      CARTRIDGE_START = 0x4020

      def initialize(
        mapper: Disconnected, ppu_registers: Disconnected, apu_registers: Disconnected, controller_ports: Disconnected
      )
        @mapper = mapper
        @ppu_registers = ppu_registers
        @apu_registers = apu_registers
        @controller_ports = controller_ports
        @ram = Array.new(RAM_SIZE, 0)
        @data_bus = 0
        @oam_dma = OamDma.new(bus: self, ppu_registers:)
      end

      # The APU slot's answer is not stored: $4015 "is internal to the CPU and so the external CPU data bus is
      # disconnected when reading it", and the rest of the slot drives nothing (plan 22, decision 2).
      def read(address)
        if address < PPU_REGISTERS_START
          @data_bus = @ram[address & RAM_MIRROR_MASK] # glossary: mirror-down
        elsif address < APU_REGISTERS_START
          @data_bus = @ppu_registers.cpu_read(address & PPU_REGISTER_MIRROR_MASK, @data_bus) # glossary: mirror-down
        elsif address < CONTROLLER_PORTS_START
          @apu_registers.cpu_read(address, @data_bus)
        elsif address < TEST_MODE_START
          @data_bus = @controller_ports.cpu_read(address, @data_bus)
        elsif address < CARTRIDGE_START
          @data_bus
        else
          @data_bus = @mapper.cpu_read(address, @data_bus)
        end
      end

      # A read by the OAM DMA unit. The 2A03 decodes its registers from "bits 4-0 from the 2A03 address bus and bits 15-5
      # from the 6502 core", and "The 6502 core keeps the same address while halted" (https://www.nesdev.org/wiki/DMA):
      # halted on the opcode fetch after the $4014 write, the core is never in $4000-$401F, so a DMA read there reaches
      # no register and leaves the data bus as it was. Any other address is read as the CPU reads it.
      def read_for_dma(address)
        return @data_bus if address >= APU_REGISTERS_START && address < CARTRIDGE_START

        read(address)
      end

      def write(address, value)
        if address < PPU_REGISTERS_START
          @ram[address & RAM_MIRROR_MASK] = value # glossary: mirror-down
        elsif address < APU_REGISTERS_START
          @ppu_registers.cpu_write(address & PPU_REGISTER_MIRROR_MASK, value) # glossary: mirror-down
        elsif address == OAMDMA
          @oam_dma.start(value)
        elsif address == CONTROLLER_STROBE
          @controller_ports.cpu_write(address, value)
        elsif address < TEST_MODE_START
          @apu_registers.cpu_write(address, value)
        elsif address >= CARTRIDGE_START
          @mapper.cpu_write(address, value)
        end
      end

      # The cycles a DMA halts the CPU for since the last call (0 almost always), for Cpu#step to add. `halt_cycle` is
      # the CPU cycle the halt falls on: the cycles the CPU has run so far.
      def take_stall_cycles(halt_cycle) = @oam_dma.take_stall_cycles(halt_cycle)
    end
  end
end

require_relative 'cpu_bus/disconnected'
require_relative 'cpu_bus/oam_dma'
