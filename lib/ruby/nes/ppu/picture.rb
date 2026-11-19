# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The picture the PPU draws: a preallocated frame buffer of 256 × 240 palette indices, row by row
      # (docs/architecture.md, Frame buffer contract). A pixel's colour is the palette RAM entry at $3F00 plus its
      # 5-bit index (https://www.nesdev.org/wiki/PPU_palettes); with greyscale (PPUMASK bit 0, told by the Ppu) the PPU
      # is "bitwise ANDing the color with $30" (https://www.nesdev.org/wiki/PPU_registers). In forced blank, with
      # rendering disabled, it draws the backdrop $3F00, but "if the current VRAM address in v points into palette RAM
      # ($3F00-$3FFF), then the color at that address will be drawn, instead" (Backdrop override). Hot path: one draw
      # per visible dot.
      class Picture
        WIDTH = 256
        HEIGHT = 240
        # The palette RAM's base on the PPU bus, and the 5 bits of an entry.
        PALETTE_START = PpuBus::PALETTE_START
        PALETTE_ENTRY_MASK = PpuBus::PaletteRam::ENTRY_MIRROR_MASK
        BACKDROP_ENTRY = 0

        attr_reader :frame_buffer

        def initialize(bus:, greyscale: false)
          @bus = bus
          @frame_buffer = Array.new(WIDTH * HEIGHT, 0)
          self.greyscale = greyscale
        end

        def greyscale=(enabled)
          @colour_mask = enabled ? PpuBus::PaletteRam::GREYSCALE_COLOUR_MASK : PpuBus::PaletteRam::COLOUR_MASK
        end

        # Stores the colour of a palette entry (0-31) at column x of row y.
        def draw(x_position, y_position, palette_entry)
          colour = @bus.read(PALETTE_START | palette_entry) # glossary: bitwise-or
          @frame_buffer[(y_position * WIDTH) + x_position] = colour & @colour_mask # glossary: bitwise-and
        end

        # Rendering is disabled: the backdrop, or the colour v points at in palette RAM.
        def draw_forced_blank(x_position, y_position, vram_address)
          address = vram_address & PpuBus::ADDRESS_MASK # glossary: low-bits
          palette_entry = address >= PALETTE_START ? address & PALETTE_ENTRY_MASK : BACKDROP_ENTRY # glossary: low-bits
          draw(x_position, y_position, palette_entry)
        end
      end
    end
  end
end
