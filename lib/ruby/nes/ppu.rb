# frozen_string_literal: true

module Ruby
  module Nes
    # The 2C02 Picture Processing Unit as the CPU sees it (https://www.nesdev.org/wiki/PPU_registers): the eight
    # registers at $2000-$2007, plugged into CpuBus's `ppu_registers:` slot, which hands them already mirrored down.
    # Behind them, the scroll registers v/t/x/w, OAM and the PPUDATA port over the PPU bus.
    #
    # PPU open bus (https://www.nesdev.org/wiki/Open_bus_behavior#PPU_open_bus): the PPU keeps its own I/O latch,
    # modelled without decay (plan 11, decision 1). "Writes to any PPU port [...] load a value onto the PPU's I/O bus";
    # reads of $2004 and $2007 load the byte read; a PPUSTATUS read loads its bits 7-5 only; the write-only registers and
    # PPUSTATUS's bits 4-0 answer the latch. The CPU's data bus never reaches it, so `cpu_read` ignores `data_bus`.
    #
    # Not yet: the VBlank, sprite 0 hit and overflow flags (bits 7-5 of PPUSTATUS read 0 until plans 12 and 14), timing,
    # NMI, and the writes ignored after reset (plan 12).
    class Ppu
      PPUCTRL = 0x2000
      PPUMASK = 0x2001
      PPUSTATUS = 0x2002
      OAMADDR = 0x2003
      OAMDATA = 0x2004
      PPUSCROLL = 0x2005
      PPUADDR = 0x2006
      PPUDATA = 0x2007

      # PPUCTRL bit 2: "VRAM address increment per CPU read/write of PPUDATA (0: add 1, going across; 1: add 32, going
      # down)".
      VRAM_INCREMENT_FLAG = 0x04
      ACROSS_INCREMENT = 1
      DOWN_INCREMENT = 32
      # PPUMASK bit 0: "Greyscale (0: normal color, 1: greyscale)".
      GREYSCALE_FLAG = 0x01
      # PPUSTATUS bits 4-0 are "PPU open bus"; its flags, bits 7-5, are all clear until plans 12 and 14.
      STATUS_OPEN_BUS_BITS = 0x1F

      def initialize(bus:, scroll_registers: ScrollRegisters.new, oam: Oam.new)
        @scroll_registers = scroll_registers
        @oam = oam
        @data_port = DataPort.new(bus:, scroll_registers:)
        @latch = 0
      end

      # The byte the register puts on the CPU data bus; `data_bus` is not read (the PPU answers from its own latch).
      def cpu_read(address, _data_bus)
        case address
        when PPUSTATUS then read_status
        when OAMDATA then @latch = @oam.read
        when PPUDATA then @latch = @data_port.read(@latch)
        else @latch
        end
      end

      # One `when` per writable register: the decoder is as wide as the register file.
      # rubocop:disable-next Metrics/CyclomaticComplexity
      def cpu_write(address, value)
        @latch = value
        case address
        when PPUCTRL then write_control(value)
        when PPUMASK then @data_port.greyscale = value.anybits?(GREYSCALE_FLAG)
        when OAMADDR then @oam.address = value
        when OAMDATA then @oam.write(value)
        when PPUSCROLL then @scroll_registers.write_scroll(value)
        when PPUADDR then @scroll_registers.write_address(value)
        when PPUDATA then @data_port.write(value)
        end
      end

      private

      # "Reading this register has the side effect of clearing the PPU's internal w register."
      def read_status
        @scroll_registers.reset_write_toggle
        @latch &= STATUS_OPEN_BUS_BITS # glossary: low-bits
      end

      def write_control(value)
        @scroll_registers.write_control(value)
        @data_port.increment = value.anybits?(VRAM_INCREMENT_FLAG) ? DOWN_INCREMENT : ACROSS_INCREMENT
      end
    end
  end
end

require_relative 'ppu/scroll_registers'
require_relative 'ppu/oam'
require_relative 'ppu/data_port'
