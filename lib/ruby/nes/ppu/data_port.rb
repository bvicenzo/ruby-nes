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
        # A palette read goes to the buffer from the nametable mirror $1000 below ($3Fxx -> $2Fxx).
        UNDERNEATH_PALETTE_OFFSET = 0x1000
        # A palette read returns the colour's 6 bits, or only bits 5-4 in greyscale; the top 2 come from the PPU's open
        # bus.
        OPEN_BUS_BITS = 0xC0

        attr_writer :increment

        def initialize(bus:, scroll_registers:, frame_timing:, increment: ACROSS_INCREMENT, greyscale: false)
          @bus = bus
          @scroll_registers = scroll_registers
          @frame_timing = frame_timing
          @increment = increment
          self.greyscale = greyscale
          @buffer = 0
        end

        def greyscale=(enabled)
          @colour_mask = enabled ? PpuBus::PaletteRam::GREYSCALE_COLOUR_MASK : PpuBus::PaletteRam::COLOUR_MASK
        end

        # The byte PPUDATA returns; `open_bus` is the PPU's I/O latch, whose top 2 bits a palette read keeps.
        def read(open_bus)
          address = @scroll_registers.vram_address & PpuBus::ADDRESS_MASK # glossary: low-bits
          if address >= PpuBus::PALETTE_START
            colour = @bus.read(address) & @colour_mask # glossary: bitwise-and
            byte = colour | (open_bus & OPEN_BUS_BITS) # glossary: bitwise-or, bitwise-and
            @buffer = @bus.read(address - UNDERNEATH_PALETTE_OFFSET)
          else
            byte = @buffer
            @buffer = @bus.read(address)
          end
          advance_vram_address
          byte
        end

        # Puts v (its low 14 bits) on the PPU's bus outside rendering, so a board watching A12 sees each move of v by
        # PPUADDR or PPUDATA: MMC3 can be clocked "by writing to $2006" (https://www.nesdev.org/wiki/MMC3), and
        # mmc3_test_2's 3-A12_clocking clocks it by a PPUDATA access taking v from $0FFF to $1000. During rendering
        # nothing is shown, a deliberate divergence (plan 21, decision 10): the MMC3 page says the $2006 clock happens
        # "regardless of whether PPU is/is not rendering", but there v's bit 12 is fine Y, and the board already sees
        # every rendering fetch, which uses v.
        def show_address
          return if @frame_timing.rendering_in_progress?

          @bus.place_address(@scroll_registers.vram_address & PpuBus::ADDRESS_MASK) # glossary: low-bits
        end

        # The PPU's reset signal clears the read buffer (https://www.nesdev.org/wiki/PPU_power_up_state).
        def clear_read_buffer
          @buffer = 0
        end

        def write(value)
          @bus.write(@scroll_registers.vram_address & PpuBus::ADDRESS_MASK, value) # glossary: low-bits
          advance_vram_address
        end

        private

        # "During rendering", the access updates v by "triggering a coarse X increment and a Y increment
        # simultaneously", "not affected by the status of the increment bit"; otherwise v advances by 1 or 32.
        def advance_vram_address
          if @frame_timing.rendering_in_progress?
            @scroll_registers.increment_coarse_x
            @scroll_registers.increment_y
          else
            @scroll_registers.increment_vram_address(@increment)
            show_address
          end
        end
      end
    end
  end
end
