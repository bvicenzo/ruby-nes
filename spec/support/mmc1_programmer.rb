# frozen_string_literal: true

# Writes an MMC1's registers the way a program does, and stands in for the CPU as the board's clock (`cpu=`, plan 20,
# decision 1). Every write lands 4 cycles after the previous one, as `STA` absolute takes 4
# (https://www.nesdev.org/wiki/6502_cycle_times), so the serial port never sees two consecutive cycles unless a spec
# asks for a read-modify-write.
#
#   programmer = Mmc1Programmer.new(board)
#   programmer.load(0x8000, 0b0_1110) # five writes, low bit first, the last one at $8000: Control = $0E
#   programmer.write(0xE000, 0x80)    # one write: the reset
#   programmer.read_modify_write(0x8000, original: 0xFF, modified: 0x00) # two writes on one cycle
class Mmc1Programmer
  CYCLES_PER_WRITE = 4
  # "the CPU writes five times with bit 7 clear and one bit of the desired value in bit 0"
  # (https://www.nesdev.org/wiki/MMC1).
  WRITES_PER_REGISTER = 5

  attr_reader :cycles

  def initialize(board)
    @board = board
    @cycles = 0
    board.cpu = self
  end

  # Loads the 5-bit `value` into the register `address` selects: bit 0 first, each write to `address`.
  def load(address, value)
    WRITES_PER_REGISTER.times { |bit| write(address, Ruby::Nes::Bits.bit_at(value, bit)) }
  end

  def write(address, value)
    @cycles += CYCLES_PER_WRITE
    @board.cpu_write(address, value)
  end

  # The two writes of a read-modify-write instruction, which the emulator makes on one cycle (Cpu#write_modified).
  def read_modify_write(address, original:, modified:)
    write(address, original)
    @board.cpu_write(address, modified)
  end
end
