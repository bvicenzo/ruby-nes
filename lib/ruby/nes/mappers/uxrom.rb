# frozen_string_literal: true

module Ruby
  module Nes
    module Mappers
      # UxROM, iNES mapper 2 (https://www.nesdev.org/wiki/UxROM): "CPU $8000-$BFFF: 16 KB switchable PRG ROM bank";
      # "CPU $C000-$FFFF: 16 KB PRG ROM bank, fixed to the last bank". A write anywhere in $8000-$FFFF selects the
      # switchable bank. "Emulator implementations of iNES mapper 2 treat this as a full 8-bit bank select register,
      # without bus conflicts" (plan 19, decision 2): the whole byte, wrapped by the PRG ROM size, is the bank. No PRG
      # RAM ("PRG RAM capacity: None"); CHR is 8 KiB of RAM; mirroring is fixed by solder pads (the header's bit). The
      # switchable bank starts at 0 (plan 19, decision 6).
      class Uxrom < Base
        private

        # The first window is the switchable one; the second keeps the last bank the base puts there.
        def write_register(_address, value) = select_prg_bank(FIRST_PRG_WINDOW, value)
      end
    end
  end
end
