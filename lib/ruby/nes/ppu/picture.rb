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
      # Colours precomputed (plan 30, decisions 1 and 4): `colours` holds the final pixel of each of the 32 palette
      # entries, rebuilt when palette RAM (which tells the picture of every write), greyscale or emphasis change. All
      # three are register writes, which catch the PPU up first, so no pixel sees a stale colour. The pixel composer draws
      # a visible pixel by storing `colours[entry]` into `drawn_frame` itself, and is the only one to complete a frame.
      #
      # Double buffering (plan 16, decision 1): the pixels go to a buffer of their own, `drawn_frame`;
      # `complete_frame`, told when the PPU enters the post-render scanline, swaps it with `frame_buffer`, so a frontend
      # always gets one whole frame. Every visible pixel is drawn every frame, so the next frame overwrites the whole
      # swapped-out buffer.
      class Picture
        WIDTH = 256
        HEIGHT = 240
        # The palette RAM's base on the PPU bus, and the 5 bits of an entry.
        PALETTE_START = PpuBus::PALETTE_START
        PALETTE_ENTRY_MASK = PpuBus::PaletteRam::ENTRY_MIRROR_MASK
        PALETTE_ENTRIES = PpuBus::PaletteRam::ENTRY_COUNT
        BACKDROP_ENTRY = 0

        # The last complete frame.
        attr_reader :frame_buffer
        # The frame being drawn, which `complete_frame` swaps with `frame_buffer`.
        attr_reader :drawn_frame
        # The pixel of each palette entry: one array for the life of the picture, rebuilt in place, so the renderer
        # keeps a reference to it.
        attr_reader :colours

        def initialize(palette_ram:, greyscale: false, emphasis: 0)
          @palette_ram = palette_ram
          @frame_buffer = Array.new(WIDTH * HEIGHT, 0)
          @drawn_frame = Array.new(WIDTH * HEIGHT, 0)
          @colours = Array.new(PALETTE_ENTRIES, 0)
          @colour_mask = colour_mask(greyscale)
          @emphasis = emphasis_bits(emphasis)
          palette_ram.observer = self
          palette_changed
        end

        def greyscale=(enabled)
          @colour_mask = colour_mask(enabled)
          palette_changed
        end

        # PPUMASK's emphasis bits, 5-7, in place (the others clear): they move to the pixel's bits 6-8.
        def emphasis=(flags)
          @emphasis = emphasis_bits(flags)
          palette_changed
        end

        # Palette RAM changed: every entry's pixel is taken again, with the greyscale mask and the emphasis.
        def palette_changed
          @colours.each_index do |entry|
            @colours[entry] = Bits.set_flag(Bits.low_bits(@palette_ram.read(entry), @colour_mask), @emphasis)
          end
        end

        # Stores the colour of a palette entry (0-31) at column x of row y.
        def draw(x_position, y_position, palette_entry)
          @drawn_frame[(y_position * WIDTH) + x_position] = @colours[palette_entry]
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

        private

        def colour_mask(greyscale)
          greyscale ? PpuBus::PaletteRam::GREYSCALE_COLOUR_MASK : PpuBus::PaletteRam::COLOUR_MASK
        end

        def emphasis_bits(flags)
          flags << 1 # glossary: shift-left
        end
      end
    end
  end
end
