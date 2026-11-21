# frozen_string_literal: true

module Ruby
  module Nes
    # Intention-revealing bit helpers for code off the hot path (docs/architecture.md, Readability). Hot paths write
    # the same operations inline with a `# glossary:` tag; each helper is documented under its anchor in
    # docs/GLOSSARY.md, "Bit operations".
    module Bits
      # The constants the glossary's inline idioms use; hot-path classes refer to them by name.
      BYTE_MASK = 0xFF
      WORD_MASK = 0xFFFF
      # Selects the page (high byte) of an address: indexed reads that change it cost a cycle
      # (https://www.nesdev.org/wiki/CPU_addressing_modes).
      PAGE_MASK = 0xFF00
      # Bit 7: the sign of a two's complement byte.
      SIGN_BIT = 0x80
      # The number of values a byte holds.
      BYTE_RANGE = 0x100
      NIBBLE_WIDTH = 4
      BYTE_WIDTH = 8
      NIBBLE_MASK = 0x0F

      # glossary: wrap-to-byte — the low 8 bits, so $100 -> $00 and -3 -> $FD: a byte-wide register overflowing.
      def self.wrap_to_byte(value) = value & BYTE_MASK

      # glossary: wrap-to-word — the low 16 bits, so $10000 -> $0000: an address wrapping past $FFFF.
      def self.wrap_to_word(value) = value & WORD_MASK

      # glossary: low-bits — only the bits a narrower register keeps, the mask being a run of ones from bit 0 ($FD with
      # $07 -> $05).
      def self.low_bits(value, mask) = value & mask

      # glossary: bit-field — a group of adjacent bits read as a number of its own (address bits 14-13 of $BFFF, mask
      # $6000 and shift 13, -> 1).
      def self.bit_field(value, mask:, shift:) = (value & mask) >> shift

      # glossary: bit-at — the bit at position `index` (0 the lowest) as 0 or 1 (%0100 at 2 -> 1).
      def self.bit_at(value, index) = (value >> index) & 1

      # glossary: high-nibble — the upper 4 bits of a byte, as 0-15 ($4A -> $4).
      def self.high_nibble(byte) = (byte >> NIBBLE_WIDTH) & NIBBLE_MASK

      # glossary: combine-nibbles — a byte from its two 4-bit halves (low: $1, high: $2 -> $21).
      def self.combine_nibbles(low:, high:) = (high << NIBBLE_WIDTH) | low

      # glossary: set-flag — the flag's bit turned on, the others untouched (%0010_0001 with $80 -> %1010_0001).
      def self.set_flag(register, flag) = register | flag

      # glossary: clear-flag — the flag's bit turned off, the others untouched (%1010_0001 with $80 -> %0010_0001).
      def self.clear_flag(register, flag) = register & ~flag

      # glossary: combine-bytes — a 16-bit word from its two bytes (low: $16, high: $80 -> $8016), as the 6502 reads a
      # little-endian address.
      def self.combine_bytes(low:, high:) = (high << BYTE_WIDTH) | low
    end
  end
end
