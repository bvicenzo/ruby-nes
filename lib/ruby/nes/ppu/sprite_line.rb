# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The sprite pixels of one scanline (plan 14, decision 6): the selected sprites "get drawn front (lower index) to
      # back (higher index) into a buffer, taking only the first opaque pixel that matches each X coordinate. Priority
      # does not affect ordering in this buffer but is saved with each pixel"
      # (https://www.nesdev.org/wiki/PPU_sprite_priority). A row is two pattern bytes in screen order, bit 7 the
      # leftmost pixel, plane 0 bit 0 and plane 1 bit 1 of the pattern value
      # (https://www.nesdev.org/wiki/PPU_pattern_tables); value 0 is transparent. Attribute bit 6, "Flip sprite
      # horizontally", reads the row from its other end. An entry is the pixel's palette entry, $10 | palette << 2 |
      # pattern value, "Palette (4 to 7)" being attribute bits 1-0 (https://www.nesdev.org/wiki/PPU_OAM,
      # https://www.nesdev.org/wiki/PPU_palettes), plus BEHIND_BACKGROUND_FLAG from attribute bit 5 and
      # SPRITE_ZERO_FLAG; 0 is a column no sprite covers. Columns past 255 are "past the right edge of the screen, thus
      # invisible". It also flags each group of 8 columns, a tile of the screen, where an opaque sprite pixel lies, so the
      # renderer composes a tile with none from the background alone (plan 31, decision 1). Hot path: filled at the
      # sprite fetches, read by the renderer once per pixel and once per whole tile.
      class SpriteLine
        WIDTH = Picture::WIDTH
        SPRITE_WIDTH = 8
        TILE_WIDTH = 8
        TILES = WIDTH / TILE_WIDTH
        EMPTY = 0
        # Sprite palette entries are $10-$1F ("Background/Sprite select").
        SPRITE_PALETTES = 0x10
        PALETTE_MASK = 0x03
        PALETTE_SHIFT = 2
        # Attribute bit 5: "Priority (0: in front of background; 1: behind background)"; the entry keeps it in place.
        BEHIND_BACKGROUND_FLAG = 0x20
        SPRITE_ZERO_FLAG = 0x40
        # The 5-bit palette entry of an entry, without its flags.
        PALETTE_ENTRY_MASK = Picture::PALETTE_ENTRY_MASK
        LEFTMOST_PIXEL_BIT = 7
        # Plane 1 gives bit 1 of the pattern value.
        HIGH_PLANE_SHIFT = 1
        FLIP_HORIZONTAL_FLAG = 0x40
        # Each byte with its bits in the opposite order, built once at load time.
        MIRRORED_BYTES = Array.new(Bits::BYTE_MASK + 1) { |byte| format('%08b', byte).reverse.to_i(2) }.freeze

        # The 256 entries, 0 where no opaque sprite pixel covers the column: one array for the life of the line, which
        # `clear` empties in place, so the renderer keeps a reference to it (plan 25, decision 7).
        attr_reader :entries

        # The 32 flags, group g being columns 8g to 8g + 7: one array for the life of the line, like the entries.
        attr_reader :occupied_tiles

        def initialize
          @entries = Array.new(WIDTH, EMPTY)
          @occupied_tiles = Array.new(TILES, false)
        end

        def clear
          @entries.fill(EMPTY)
          @occupied_tiles.fill(false)
        end

        # Puts a sprite's row from column x, keeping the pixels of the sprites placed before it.
        def place(x_position, pattern_low, pattern_high, attributes, sprite_zero)
          flags = pixel_flags(attributes, sprite_zero)
          if (attributes & FLIP_HORIZONTAL_FLAG) != 0 # glossary: flag-set
            pattern_low = MIRRORED_BYTES[pattern_low]
            pattern_high = MIRRORED_BYTES[pattern_high]
          end
          column = 0
          while column < SPRITE_WIDTH && x_position + column < WIDTH
            bit = LEFTMOST_PIXEL_BIT - column
            high_plane = ((pattern_high >> bit) & 1) << HIGH_PLANE_SHIFT # glossary: bit-at, place-bit-field
            pattern_value = high_plane | ((pattern_low >> bit) & 1) # glossary: bitwise-or, bit-at
            put(x_position + column, flags | pattern_value) unless pattern_value.zero? # glossary: bitwise-or
            column += 1
          end
        end

        private

        def pixel_flags(attributes, sprite_zero)
          palette = (attributes & PALETTE_MASK) << PALETTE_SHIFT # glossary: place-bit-field
          flags = SPRITE_PALETTES | palette | (attributes & BEHIND_BACKGROUND_FLAG) # glossary: bitwise-or, bitwise-and
          sprite_zero ? flags | SPRITE_ZERO_FLAG : flags # glossary: set-flag
        end

        def put(column, entry)
          @entries[column] = entry if @entries[column] == EMPTY
          @occupied_tiles[column / TILE_WIDTH] = true
        end
      end
    end
  end
end
