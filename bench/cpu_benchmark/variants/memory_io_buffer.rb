# frozen_string_literal: true

# Variant for decision 2 of docs/architecture.md: memory as an IO::Buffer read with `get_value(:U8, offset)` and
# written with `set_value(:U8, offset, value)`, instead of an Array of Integer. Covers what the CPU touches on
# nestest: the CpuBus's internal RAM and the board's PRG ROM and PRG RAM (Mappers::Base since plan 19). The arrays are
# converted once, when the console is built. IO::Buffer is experimental on Ruby 4.0.9; its warning (on standard error)
# is silenced to keep the run's output clean.
Warning[:experimental] = false

module Ruby
  module Nes
    # The RAM becomes an IO::Buffer after the original constructor runs.
    module BufferRam
      def initialize(...)
        super
        @ram = IO::Buffer.for(@ram.pack('C*')).dup
      end
    end

    class CpuBus
      prepend BufferRam

      def read(address)
        @data_bus =
          if address < PPU_REGISTERS_START
            @ram.get_value(:U8, address & RAM_MIRROR_MASK) # glossary: mirror-down
          elsif address < APU_REGISTERS_START
            @ppu_registers.cpu_read(address & PPU_REGISTER_MIRROR_MASK, @data_bus) # glossary: mirror-down
          elsif address < CONTROLLER_PORTS_START
            @apu_registers.cpu_read(address, @data_bus)
          elsif address < TEST_MODE_START
            @controller_ports.cpu_read(address, @data_bus)
          elsif address < CARTRIDGE_START
            @data_bus
          else
            @mapper.cpu_read(address, @data_bus)
          end
      end

      def write(address, value)
        if address < PPU_REGISTERS_START
          @ram.set_value(:U8, address & RAM_MIRROR_MASK, value) # glossary: mirror-down
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
    end

    module Mappers
      # PRG ROM and PRG RAM become IO::Buffers after the original constructor runs; the ROM's is read-only.
      module BufferPrgMemory
        def initialize(...)
          super
          @prg_rom = IO::Buffer.for(@prg_rom.pack('C*'))
          @prg_ram = IO::Buffer.for(@prg_ram.pack('C*')).dup
        end
      end

      class Base
        prepend BufferPrgMemory

        def cpu_read(address, data_bus)
          if address >= PRG_ROM_START
            window = (address & PRG_WINDOW_SELECT_MASK) >> PRG_WINDOW_SELECT_SHIFT # glossary: bit-field
            offset = @prg_window_offsets[window] + (address & PRG_WINDOW_OFFSET_MASK) # glossary: low-bits
            @prg_rom.get_value(:U8, offset)
          elsif address >= PRG_RAM_START && @prg_ram_present
            @prg_ram.get_value(:U8, address & PRG_RAM_MIRROR_MASK) # glossary: mirror-down
          else
            data_bus
          end
        end

        def cpu_write(address, value)
          if address >= PRG_ROM_START
            write_register(address, value)
          elsif address >= PRG_RAM_START && @prg_ram_present
            @prg_ram.set_value(:U8, address & PRG_RAM_MIRROR_MASK, value) # glossary: mirror-down
          end
        end
      end
    end
  end
end
