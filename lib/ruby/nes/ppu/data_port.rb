# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # PPUDATA, $2007 (https://www.nesdev.org/wiki/PPU_registers): the CPU's window on the PPU bus at v. A read returns
      # "the contents of an internal read buffer" and refills the buffer from v, so data arrives one read late; the
      # buffer starts at $00 (https://www.nesdev.org/wiki/PPU_power_up_state). Palette data "is returned immediately
      # instead of going to the internal read buffer", with "PPU open bus in the top 2 bits" and greyscale "bitwise
      # ANDing the color with $30", while the buffer takes "a normal read from PPU memory at the specified address,
      # "underneath" the palette data": the nametable byte $1000 below (plan 11, decision 8). Every access then adds 1
      # or 32 to v (https://www.nesdev.org/wiki/PPU_scrolling), which "has 15 bits" while the bus has 14: "The highest
      # bit is unused for access through $2007". The PPU tells the port its increment (PPUCTRL bit 2) and greyscale
      # (PPUMASK bit 0) when those registers are written.
      class DataPort
        # The PPU bus is 14 bits wide.
        BUS_ADDRESS_MASK = 0x3FFF
        # A palette read goes to the buffer from the nametable mirror $1000 below ($3Fxx -> $2Fxx).
        UNDERNEATH_PALETTE_OFFSET = 0x1000
        # A palette read returns the colour's 6 bits, or only bits 5-4 in greyscale; the top 2 come from the PPU's open
        # bus.
        GREYSCALE_COLOUR_MASK = 0x30
        OPEN_BUS_BITS = 0xC0

        attr_writer :increment

        def initialize(bus:, scroll_registers:, increment: ACROSS_INCREMENT, greyscale: false)
          @bus = bus
          @scroll_registers = scroll_registers
          @increment = increment
          self.greyscale = greyscale
          @buffer = 0
        end

        def greyscale=(enabled)
          @colour_mask = enabled ? GREYSCALE_COLOUR_MASK : PpuBus::PaletteRam::COLOUR_MASK
        end

        # The byte PPUDATA returns; `open_bus` is the PPU's I/O latch, whose top 2 bits a palette read keeps.
        def read(open_bus)
          address = @scroll_registers.vram_address & BUS_ADDRESS_MASK # glossary: low-bits
          if address >= PpuBus::PALETTE_START
            colour = @bus.read(address) & @colour_mask # glossary: bitwise-and
            byte = colour | (open_bus & OPEN_BUS_BITS) # glossary: bitwise-or, bitwise-and
            @buffer = @bus.read(address - UNDERNEATH_PALETTE_OFFSET)
          else
            byte = @buffer
            @buffer = @bus.read(address)
          end
          @scroll_registers.increment_vram_address(@increment)
          byte
        end

        def write(value)
          @bus.write(@scroll_registers.vram_address & BUS_ADDRESS_MASK, value) # glossary: low-bits
          @scroll_registers.increment_vram_address(@increment)
        end
      end
    end
  end
end
