# frozen_string_literal: true

# A CPU bus double with 64 KiB of plain memory and no address decoding, so CPU specs do not depend on CpuBus mirrors
# (plan 05, decision 5). Addresses outside $0000-$FFFF and values outside a byte raise, so a missing 16-bit or 8-bit
# wrap in the CPU fails loudly instead of reading a neighbour (a negative Array index would read from the end) or
# storing a value no byte-wide bus could hold.
#
#   bus = FlatBus.new
#   bus.write(0x10FF, 0x34)
#   bus.read(0x10FF) # => 0x34
#   bus.write_bytes(0x8000, [0xA9, 0x42]) # a program: LDA #$42
class FlatBus
  SIZE = 0x10000
  BYTE_VALUES = (0x00..0xFF)

  def initialize
    @memory = Array.new(SIZE, 0)
  end

  def read(address)
    @memory[checked_address(address)]
  end

  def write(address, value)
    raise ArgumentError, "value #{hexadecimal(value, digits: 2)} is not a byte" unless BYTE_VALUES.cover?(value)

    @memory[checked_address(address)] = value
  end

  def write_bytes(address, bytes)
    bytes.each_with_index { |byte, offset| write(address + offset, byte) }
  end

  private

  def checked_address(address)
    unless address.between?(0, SIZE - 1)
      raise ArgumentError, "address #{hexadecimal(address, digits: 4)} is outside $0000-$FFFF"
    end

    address
  end

  def hexadecimal(number, digits:)
    sign = number.negative? ? '-' : ''
    "#{sign}$#{format('%0*X', digits, number.abs)}"
  end
end
