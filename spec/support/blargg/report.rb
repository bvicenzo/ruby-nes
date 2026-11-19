# frozen_string_literal: true

module Blargg
  # What a blargg ROM wrote at $6000 ("Output at $6000" in the suites' readmes), read through a CPU bus: "$80 means the
  # test is running, $81 means the test needs the reset button pressed, but delayed by at least 100 msec from now.
  # $00-$7F means the test has completed and given that result code"; the text starts at $6004 "with a zero-byte
  # terminator at the end"; $DE $B0 $61 at $6001-$6003 tell the data is valid (the readme prints the last one as
  # "$G1"; the ROMs store $61). A status above $81 is not defined by the readme and reads as running.
  class Report
    STATUS_ADDRESS = 0x6000
    SIGNATURE_ADDRESS = 0x6001
    SIGNATURE = [0xDE, 0xB0, 0x61].freeze
    TEXT_ADDRESS = 0x6004
    # The text cannot run past PRG RAM.
    PRG_RAM_END = 0x7FFF
    RUNNING = 0x80
    RESET_REQUESTED = 0x81

    def initialize(bus)
      @bus = bus
    end

    # :absent (no signature yet), :running, :reset_requested or :finished.
    def state
      return :absent unless signed?

      status = code
      if status == RESET_REQUESTED then :reset_requested
      elsif status >= RUNNING then :running
      else :finished
      end
    end

    # The status byte: the result code once finished, 0 meaning passed.
    def code = @bus.read(STATUS_ADDRESS)

    def text
      bytes = []
      address = TEXT_ADDRESS
      while address <= PRG_RAM_END
        byte = @bus.read(address)
        break if byte.zero?

        bytes << byte
        address += 1
      end
      bytes.pack('C*').force_encoding(Encoding::US_ASCII)
    end

    private

    def signed? = SIGNATURE.each_with_index.all? { |byte, offset| @bus.read(SIGNATURE_ADDRESS + offset) == byte }
  end
end
