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
        # The byte of its sprite an address holds: 0 Y, 1 tile, 2 attributes, 3 X.
        SPRITE_BYTE_MASK = 0x03
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

        # OAMDATA write: stores the byte at OAMADDR, then moves OAMADDR to the next byte.
        def write(value)
          @bytes[@address] = value & WRITABLE_BITS[@address & SPRITE_BYTE_MASK] # glossary: bitwise-and, low-bits
          @address = (@address + 1) & Bits::BYTE_MASK # glossary: wrap-to-byte
        end
      end
    end
  end
end
