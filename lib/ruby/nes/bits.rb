# frozen_string_literal: true

module Ruby
  module Nes
    # Intention-revealing bit helpers for code off the hot path (docs/architecture.md, Readability). Hot paths write
    # the same operations inline with a `# glossary:` tag; each helper is documented under its anchor in
    # docs/GLOSSARY.md, "Bit operations".
    module Bits
      NIBBLE_WIDTH = 4
      NIBBLE_MASK = 0x0F

      # glossary: high-nibble — the upper 4 bits of a byte, as 0-15 ($4A -> $4).
      def self.high_nibble(byte) = (byte >> NIBBLE_WIDTH) & NIBBLE_MASK

      # glossary: combine-nibbles — a byte from its two 4-bit halves (low: $1, high: $2 -> $21).
      def self.combine_nibbles(low:, high:) = (high << NIBBLE_WIDTH) | low
    end
  end
end
