# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The VBlank flag (PPUSTATUS bit 7) and the /NMI output it drives with PPUCTRL bit 7: "The PPU pulls /NMI low if
      # and only if both vblank_flag and NMI_output are true" (https://www.nesdev.org/wiki/NMI). FrameTiming tells it
      # when VBlank starts and ends; the Ppu tells it PPUCTRL's NMI enable and PPUSTATUS reads, which clear the flag
      # (https://www.nesdev.org/wiki/PPU_registers). It tells `nmi_output.nmi_output_changed` the /NMI level (`true`
      # while asserted) only when the level changes. The flag is clear at power by convention (plan 12, decision 8);
      # the race of a read on the dot before the flag is set belongs to FrameTiming. Specs may give the state as
      # keywords.
      class VerticalBlank
        def initialize(nmi_output:, flag_set: false, nmi_enabled: false)
          @nmi_output = nmi_output
          @flag_set = flag_set
          @nmi_enabled = nmi_enabled
        end

        def flag_set? = @flag_set

        def nmi_enabled? = @nmi_enabled

        def vertical_blank_started
          change_level { @flag_set = true }
        end

        def vertical_blank_ended
          change_level { @flag_set = false }
        end

        # PPUCTRL bit 7: enabling it while the flag is set "will immediately trigger an NMI".
        def nmi_enabled=(enabled)
          change_level { @nmi_enabled = enabled }
        end

        # PPUSTATUS read: whether the flag was set; the read clears it.
        def read
          flag_was_set = @flag_set
          change_level { @flag_set = false }
          flag_was_set
        end

        private

        # Runs the state change, then tells the output the /NMI level if it moved.
        def change_level
          level_before = nmi_level
          yield
          level_after = nmi_level
          @nmi_output.nmi_output_changed(level_after) unless level_after == level_before
        end

        def nmi_level = @flag_set && @nmi_enabled
      end
    end
  end
end
