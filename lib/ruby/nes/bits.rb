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
      NIBBLE_MASK = 0x0F

      # glossary: wrap-to-byte — the low 8 bits, so $100 -> $00 and -3 -> $FD: a byte-wide register overflowing.
      def self.wrap_to_byte(value) = value & BYTE_MASK

      # glossary: wrap-to-word — the low 16 bits, so $10000 -> $0000: an address wrapping past $FFFF.
      def self.wrap_to_word(value) = value & WORD_MASK

      # glossary: high-nibble — the upper 4 bits of a byte, as 0-15 ($4A -> $4).
      def self.high_nibble(byte) = (byte >> NIBBLE_WIDTH) & NIBBLE_MASK

      # glossary: combine-nibbles — a byte from its two 4-bit halves (low: $1, high: $2 -> $21).
      def self.combine_nibbles(low:, high:) = (high << NIBBLE_WIDTH) | low
    end
  end
end
