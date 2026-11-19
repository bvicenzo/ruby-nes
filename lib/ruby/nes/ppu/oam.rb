# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Object Attribute Memory (https://www.nesdev.org/wiki/PPU_OAM): 64 sprites of 4 bytes (Y, tile, attributes, X)
      # and OAMADDR, the byte the CPU reaches through OAMDATA. "Writes will increment OAMADDR after the write; reads do
      # not" (https://www.nesdev.org/wiki/PPU_registers); OAMADDR is a byte, so it wraps from $FF to $00. Byte 2's bits
      # 4-2 are "Unimplemented (read 0)", cleared here on write (plan 11, decision 7). Starts all zero; the contents at
      # power-up are "unspecified"; specs may give OAMADDR as a keyword.
      class Oam
        SIZE = 256
        SPRITE_COUNT = 64
        # A sprite is 4 bytes, Y, tile, attributes and X: the address of its byte 0 is its number shifted left by 2, and
        # an address's low 2 bits are the byte of its sprite it holds.
        SPRITE_SIZE_SHIFT = 2
        SPRITE_SIZE = 1 << SPRITE_SIZE_SHIFT
        SPRITE_BYTE_MASK = 0x03
        TILE_OFFSET = 1
        ATTRIBUTES_OFFSET = 2
        X_POSITION_OFFSET = 3
        # What each sprite byte keeps of a write: attributes ($E3) lose their unimplemented bits 4-2.
        WRITABLE_BITS = [0xFF, 0xFF, 0xE3, 0xFF].freeze

        # OAMADDR.
        attr_accessor :address

        def initialize(address: 0)
          @bytes = Array.new(SIZE, 0)
          @address = address
        end

        # OAMDATA read: the byte at OAMADDR, which stays where it is.
        def read = @bytes[@address]

        # The byte at any address (0-255), for the sprite evaluation; OAMADDR stays where it is.
        def byte(address) = @bytes[address]

        # OAMDATA write: stores the byte at OAMADDR, then moves OAMADDR to the next byte.
        def write(value)
          @bytes[@address] = value & WRITABLE_BITS[@address & SPRITE_BYTE_MASK] # glossary: bitwise-and, low-bits
          @address = (@address + 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
        end
      end
    end
  end
end
