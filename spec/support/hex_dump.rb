# frozen_string_literal: true

# Writes binary fixtures the way a hex editor shows them, one byte per pair of digits; spaces and line breaks between
# them are ignored:
#
#   HexDump.bytes('4E 45 53 1A 02 01') # => "NES\x1A\x02\x01" (binary)
module HexDump
  WHOLE_BYTES = /\A(?:\h\h)*\z/

  def self.bytes(dump)
    digits = dump.gsub(/\s/, '')
    raise ArgumentError, "not a hex dump of whole bytes: #{dump.inspect}" unless digits.match?(WHOLE_BYTES)

    [digits].pack('H*')
  end
end
