# frozen_string_literal: true

module Ruby
  module Nes
    class PpuBus
      # The PPU's internal palette memory, reached at $3F00-$3FFF (https://www.nesdev.org/wiki/PPU_palettes): 32
      # entries, eight palettes of four, the first four for the background and the last four for sprites. "Each byte in
      # this palette RAM contains a 6-bit color value", so a write keeps the low 6 bits. "$3F20-$3FFF ... Mirrors of
      # $3F00-$3F1F" (https://www.nesdev.org/wiki/PPU_memory_map). Entry 0 of each sprite palette is the same storage as
      # entry 0 of the matching background palette: "writing to either one updates the same internal storage", so
      # $3F10, $3F14, $3F18 and $3F1C reach $3F00, $3F04, $3F08 and $3F0C. Starts all zero (the power-up contents are
      # "unspecified"). The PPU bus only hands addresses from $3F00.
      class PaletteRam
        ENTRY_COUNT = 32
        # $3F20-$3FFF fold onto the 32 entries.
        ENTRY_MIRROR_MASK = 0x1F
        # A colour is one of the PPU's 64: 6 bits.
        COLOUR_MASK = 0x3F
        # Greyscale (PPUMASK bit 0) is "bitwise ANDing the color with $30" (https://www.nesdev.org/wiki/PPU_registers).
        GREYSCALE_COLOUR_MASK = 0x30
        ENTRIES_PER_PALETTE = 4
        SPRITE_PALETTES_START = 0x10

        # The entry an address stores into: itself, except entry 0 of a sprite palette, which is entry 0 of the
        # background palette 16 entries below.
        def self.storage_entry(entry)
          shared_with_background = entry >= SPRITE_PALETTES_START && (entry % ENTRIES_PER_PALETTE).zero?
          shared_with_background ? entry - SPRITE_PALETTES_START : entry
        end
        private_class_method :storage_entry

        # The storage entry of each of the 32 addresses, computed once.
        STORAGE_ENTRY = Array.new(ENTRY_COUNT) { |entry| storage_entry(entry) }.freeze

        def initialize
          @entries = Array.new(ENTRY_COUNT, 0)
        end

        def read(address)
          @entries[STORAGE_ENTRY[address & ENTRY_MIRROR_MASK]] # glossary: mirror-down
        end

        def write(address, colour)
          @entries[STORAGE_ENTRY[address & ENTRY_MIRROR_MASK]] = colour & COLOUR_MASK # glossary: mirror-down, low-bits
        end
      end
    end
  end
end
