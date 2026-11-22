# frozen_string_literal: true

module Ruby
  module Nes
    module Input
      # A standard controller (https://www.nesdev.org/wiki/Standard_controller): the frontend sets the buttons held, the
      # CPU strobes it through $4016 and reads it one button per read. Bit 0 of the strobe write is S: "Writing 1 to
      # $4016 causes the register to fill its parallel inputs from the buttons currently held", and while S stays high
      # reads "will keep returning the current state of the first button (A)". "Once S goes low, this reloading will
      # stop": the buttons are latched as it falls, and a write of 0 with S already low reloads nothing (plan 15,
      # decision 3). Reads then report "A, B, Select, Start, Up, Down, Left, Right", "1 if pressed", and "All subsequent
      # reads will return 1 on official Nintendo brand controllers" (https://www.nesdev.org/wiki/Controller_reading;
      # the same on https://www.nesdev.org/wiki/Standard_controller).
      class Controller
        # Each button's bit in the mask the frontend sets: the report order, A first.
        BUTTONS = {
          a: 0x01,
          b: 0x02,
          select: 0x04,
          start: 0x08,
          up: 0x10,
          down: 0x20,
          left: 0x40,
          right: 0x80
        }.freeze
        # Bit 0 of the $4016 write; "Other bits are ignored".
        STROBE_BIT = 0x01
        # Shifted in from the top on every read, so the 9th read on returns 1.
        FILL_BIT = 0x80

        # The buttons held, a mask of BUTTONS; the frontend sets it as the player presses and releases them.
        attr_writer :buttons

        def initialize(buttons: 0)
          @buttons = buttons
          @shift_register = 0
          @strobe = false
        end

        # The byte the CPU wrote to $4016. While S was high the register kept reloading, so the buttons held now are
        # what a fall of S latches.
        def strobe(value)
          @shift_register = @buttons if @strobe
          @strobe = (value & STROBE_BIT) != 0 # glossary: flag-set
        end

        # The bit the controller drives on D0 for this read, 0 or 1.
        def read
          return @buttons & 1 if @strobe # glossary: bit-at

          reported = @shift_register & 1 # glossary: bit-at
          @shift_register = (@shift_register >> 1) | FILL_BIT # glossary: shift-right, set-flag
          reported
        end
      end
    end
  end
end
