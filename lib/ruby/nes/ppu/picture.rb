# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The picture the PPU draws: preallocated frame buffers of 256 × 240 pixels, row by row (docs/architecture.md,
      # Frame buffer contract). A pixel's colour is the palette RAM entry at $3F00 plus its 5-bit index
      # (https://www.nesdev.org/wiki/PPU_palettes); with greyscale (PPUMASK bit 0, told by the Ppu) the PPU is "bitwise
      # ANDing the color with $30" (https://www.nesdev.org/wiki/PPU_registers). In forced blank, with rendering
      # disabled, it draws the backdrop $3F00, but "if the current VRAM address in v points into palette RAM
      # ($3F00-$3FFF), then the color at that address will be drawn, instead" (Backdrop override).
      #
      # Colour emphasis (plan 16, decision 2): PPUMASK bits 5-7, told by the Ppu, go to bits 6-8 of every pixel, so a
      # pixel is 0-511: the colour plus "Emphasize red", "Emphasize green" and "Emphasize blue" on NTSC. "The emphasis
      # bits are applied independently of greyscale" (https://www.nesdev.org/wiki/Colour_emphasis).
      #
      # Double buffering (plan 16, decision 1): the pixels go to a buffer of their own; `complete_frame`, told when the
      # PPU enters the post-render scanline, swaps it with `frame_buffer`, so a frontend always gets one whole frame.
      # Every visible pixel is drawn every frame, so the next frame overwrites the whole swapped-out buffer. Hot path:
      # one draw per visible dot, reading palette RAM directly rather than through the PPU bus (plan 25, decision 7).
      class Picture
        WIDTH = 256
        HEIGHT = 240
        # The palette RAM's base on the PPU bus, and the 5 bits of an entry.
        PALETTE_START = PpuBus::PALETTE_START
        PALETTE_ENTRY_MASK = PpuBus::PaletteRam::ENTRY_MIRROR_MASK
        BACKDROP_ENTRY = 0

        # The last complete frame.
        attr_reader :frame_buffer

        def initialize(palette_ram:, greyscale: false, emphasis: 0)
          @palette_ram = palette_ram
          @frame_buffer = Array.new(WIDTH * HEIGHT, 0)
          @drawn_frame = Array.new(WIDTH * HEIGHT, 0)
          self.greyscale = greyscale
          self.emphasis = emphasis
        end

        def greyscale=(enabled)
          @colour_mask = enabled ? PpuBus::PaletteRam::GREYSCALE_COLOUR_MASK : PpuBus::PaletteRam::COLOUR_MASK
        end

        # PPUMASK's emphasis bits, 5-7, in place (the others clear): they move to the pixel's bits 6-8.
        def emphasis=(flags)
          @emphasis = flags << 1 # glossary: shift-left
        end

        # Stores the colour of a palette entry (0-31) at column x of row y.
        def draw(x_position, y_position, palette_entry)
          colour = @palette_ram.read(palette_entry)
          pixel = (colour & @colour_mask) | @emphasis # glossary: bitwise-and, bitwise-or
          @drawn_frame[(y_position * WIDTH) + x_position] = pixel
        end

        # Rendering is disabled: the backdrop, or the colour v points at in palette RAM.
        def draw_forced_blank(x_position, y_position, vram_address)
          address = vram_address & PpuBus::ADDRESS_MASK # glossary: low-bits
          palette_entry = address >= PALETTE_START ? address & PALETTE_ENTRY_MASK : BACKDROP_ENTRY # glossary: low-bits
          draw(x_position, y_position, palette_entry)
        end

        # The frame drawn so far becomes `frame_buffer`; the next one is drawn over the previous frame's buffer. Returns
        # nil: a parallel assignment as the last expression would build an array of both buffers on every frame.
        def complete_frame
          @drawn_frame, @frame_buffer = @frame_buffer, @drawn_frame
          nil
        end
      end
    end
  end
end
