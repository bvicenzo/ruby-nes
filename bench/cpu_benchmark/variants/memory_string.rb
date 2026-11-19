# frozen_string_literal: true

# Variant for decision 2 of docs/architecture.md: memory as a binary String read with `getbyte` and written with
# `setbyte`, instead of an Array of Integer. Covers what the CPU touches on nestest: the CpuBus's internal RAM and
# NROM's PRG ROM and PRG RAM. The arrays are converted once, when the console is built.
module Ruby
  module Nes
    # The RAM becomes a String after the original constructor runs.
    module StringRam
      def initialize(...)
        super
        @ram = @ram.pack('C*')
      end
    end

    class CpuBus
      prepend StringRam

      def read(address)
        @data_bus =
          if address < PPU_REGISTERS_START
            @ram.getbyte(address & RAM_MIRROR_MASK) # glossary: mirror-down
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
          @ram.setbyte(address & RAM_MIRROR_MASK, value) # glossary: mirror-down
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
    end

    module Mappers
      # PRG ROM and PRG RAM become Strings after the original constructor runs.
      module StringPrgMemory
        def initialize(...)
          super
          @prg_rom = @prg_rom.pack('C*')
          @prg_ram = @prg_ram.pack('C*')
        end
      end

      class Nrom
        prepend StringPrgMemory

        def cpu_read(address, data_bus)
          if address >= PRG_ROM_START
            @prg_rom.getbyte(address & @prg_rom_mirror_mask) # glossary: mirror-down
          elsif address >= PRG_RAM_START
            @prg_ram.getbyte(address & PRG_RAM_MIRROR_MASK) # glossary: mirror-down
          else
            data_bus
          end
        end

        def cpu_write(address, value)
          return if address < PRG_RAM_START || address >= PRG_ROM_START

          @prg_ram.setbyte(address & PRG_RAM_MIRROR_MASK, value) # glossary: mirror-down
        end
      end
    end
  end
end
