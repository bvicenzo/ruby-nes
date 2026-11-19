# frozen_string_literal: true

module Ruby
  module Nes
    # The CPU's view of the 64 KiB address space (https://www.nesdev.org/wiki/CPU_memory_map): the 2 KiB of internal
    # RAM and three mirrors, the PPU registers mirrored every 8 bytes, the APU and I/O registers, the disabled test
    # range, and the cartridge. Devices plug into slots and answer `cpu_read(address, data_bus)` with the byte left on
    # the data bus, and `cpu_write(address, value)`; an empty slot is Disconnected.
    #
    # Open bus (https://www.nesdev.org/wiki/Open_bus_behavior): "reading open bus repeats the last value that was read
    # from the bus before this read". Every read stores its result as the data bus value, and a device that does not
    # drive the bus returns that value untouched. Writes do not change it: the page documents reads only.
    #
    # The bus owns the OAM DMA unit (plan 11, decision 2): a write to OAMDMA ($4014) starts it instead of reaching the
    # APU and I/O slot, and the stall it costs the CPU comes back through #take_stall_cycles, which Cpu#step adds.
    class CpuBus
      RAM_SIZE = 0x0800
      # $0800-$1FFF repeat the 2 KiB of RAM.
      RAM_MIRROR_MASK = 0x07FF
      PPU_REGISTERS_START = 0x2000
      # $2008-$3FFF repeat $2000-$2007 every 8 bytes.
      PPU_REGISTER_MIRROR_MASK = 0x2007
      IO_REGISTERS_START = 0x4000
      # "OAM DMA copies 256 bytes from a CPU page to PPU OAM" (https://www.nesdev.org/wiki/DMA).
      OAMDMA = 0x4014
      # "APU and I/O functionality that is normally disabled": nothing answers $4018-$401F.
      TEST_MODE_START = 0x4018
      CARTRIDGE_START = 0x4020

      def initialize(mapper: Disconnected, ppu_registers: Disconnected, io_registers: Disconnected)
        @mapper = mapper
        @ppu_registers = ppu_registers
        @io_registers = io_registers
        @ram = Array.new(RAM_SIZE, 0)
        @data_bus = 0
        @oam_dma = OamDma.new(bus: self, ppu_registers:)
      end

      def read(address)
        @data_bus =
          if address < PPU_REGISTERS_START
            @ram[address & RAM_MIRROR_MASK] # glossary: mirror-down
          elsif address < IO_REGISTERS_START
            @ppu_registers.cpu_read(address & PPU_REGISTER_MIRROR_MASK, @data_bus) # glossary: mirror-down
          elsif address < TEST_MODE_START
            @io_registers.cpu_read(address, @data_bus)
          elsif address < CARTRIDGE_START
            @data_bus
          else
            @mapper.cpu_read(address, @data_bus)
          end
      end

      def write(address, value)
        if address < PPU_REGISTERS_START
          @ram[address & RAM_MIRROR_MASK] = value # glossary: mirror-down
        elsif address < IO_REGISTERS_START
          @ppu_registers.cpu_write(address & PPU_REGISTER_MIRROR_MASK, value) # glossary: mirror-down
        elsif address == OAMDMA
          @oam_dma.start(value)
        elsif address < TEST_MODE_START
          @io_registers.cpu_write(address, value)
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
