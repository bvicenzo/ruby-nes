# frozen_string_literal: true

module Blargg
  # Tiny programs that speak blargg's "Output at $6000" protocol, for the runner's specs. Each loads at $8000 (the reset
  # vector of Cartridges.with_program) and first writes the signature $DE $B0 $61 to $6001-$6003.
  module Programs
    SIGNATURE = HexDump.bytes(<<~HEX).bytes.freeze
      A9 DE 8D 01 60
      A9 B0 8D 02 60
      A9 61 8D 03 60
    HEX

    # $800F: status $80 (running), "A" at $6004, then loops on itself forever.
    KEEPS_RUNNING = (SIGNATURE + HexDump.bytes(<<~HEX).bytes).freeze
      A9 80 8D 00 60
      A9 41 8D 04 60
      4C 19 80
    HEX

    # $800F: a first boot (RAM $00 still zero) marks $00 and asks for a reset ($81); after the reset, status $00.
    #   800F LDA $00 / BNE $801D / INC $00 / LDA #$81 / STA $6000 / JMP $801A
    #   801D LDA #$00 / STA $6000 / JMP $8022
    REQUESTS_RESET = (SIGNATURE + HexDump.bytes(<<~HEX).bytes).freeze
      A5 00 D0 0A
      E6 00 A9 81 8D 00 60 4C 1A 80
      A9 00 8D 00 60 4C 22 80
    HEX

    # As REQUESTS_RESET, but after the reset the status still reads $81 for about 11 frames (two nested 256-step
    # loops, some 329 000 cycles) before it turns to $00.
    #   801D LDX #$00 / 801F LDY #$00 / 8021 DEY / BNE $8021 / DEX / BNE $801F
    #   8027 LDA #$00 / STA $6000 / JMP $802C
    REQUESTS_RESET_THEN_LINGERS = (SIGNATURE + HexDump.bytes(<<~HEX).bytes).freeze
      A5 00 D0 0A
      E6 00 A9 81 8D 00 60 4C 1A 80
      A2 00 A0 00 88 D0 FD CA D0 F8
      A9 00 8D 00 60 4C 2C 80
    HEX

    # $800F: "OK" at $6004 (the zero after it is PRG RAM's power-up state here), status $03, then loops.
    FINISHES = (SIGNATURE + HexDump.bytes(<<~HEX).bytes).freeze
      A9 4F 8D 04 60
      A9 4B 8D 05 60
      A9 03 8D 00 60
      4C 1E 80
    HEX
  end
end
