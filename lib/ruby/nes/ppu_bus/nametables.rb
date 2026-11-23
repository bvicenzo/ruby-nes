# frozen_string_literal: true

module Ruby
  module Nes
    class PpuBus
      # The nametable memory the PPU reaches at $2000-$3EFF (https://www.nesdev.org/wiki/PPU_nametables): four logical
      # nametables of 1 KiB ($2000, $2400, $2800, $2C00) over physical pages of VRAM chosen by the board's mirroring
      # (https://www.nesdev.org/wiki/Mirroring), and "$3000-3EFF is usually a mirror of the 2kB region from $2000-2EFF"
      # (https://www.nesdev.org/wiki/PPU_memory_map). The console has 2 KiB of VRAM (CIRAM, pages 0 and 1); a
      # four-screen board brings 2 KiB more (pages 2 and 3), held here too (plan 11, decision 5). Boards such as MMC1
      # change the mirroring at runtime (plan 11, decision 6), and tell the nametables each change instead of being asked
      # on every access (plan 30, decision 3). The PPU bus only hands addresses in $2000-$3EFF.
      class Nametables
        NAMETABLE_SIZE = 0x0400
        PAGE_COUNT = 4
        # Address bits 10-11 select the logical nametable; $3000-$3EFF select the same as $2000-$2EFF.
        NAMETABLE_SELECT_MASK = 0x0C00
        NAMETABLE_SELECT_SHIFT = 10
        NAMETABLE_OFFSET_MASK = 0x03FF

        # The physical page of each logical nametable, $2000/$2400/$2800/$2C00, for each mirroring mode, named as the
        # Mirroring page and the iNES header name them: horizontal "connect[s] PPU A11 to CIRAM A10", vertical "PPU A10
        # to CIRAM A10", single-screen ties CIRAM A10 to the "lower bank" or the "upper bank", four-screen has "4
        # unique nametables".
        PHYSICAL_PAGES = {
          horizontal: [0, 0, 1, 1].freeze,
          vertical: [0, 1, 0, 1].freeze,
          single_screen_lower: [0, 0, 0, 0].freeze,
          single_screen_upper: [1, 1, 1, 1].freeze,
          four_screen: [0, 1, 2, 3].freeze
        }.freeze

        # Gives itself to the board, which tells it every mirroring it selects from then on (plan 30, decision 3).
        def initialize(mapper:)
          @vram = Array.new(NAMETABLE_SIZE * PAGE_COUNT, 0)
          mirroring_changed(mapper.mirroring)
          mapper.nametables = self
        end

        # The board selected a mirroring: the physical page of each logical nametable from now on.
        def mirroring_changed(mirroring)
          @physical_pages = PHYSICAL_PAGES.fetch(mirroring)
        end

        def read(address) = @vram[vram_index(address)]

        def write(address, value)
          @vram[vram_index(address)] = value
        end

        private

        def vram_index(address)
          logical_nametable = (address & NAMETABLE_SELECT_MASK) >> NAMETABLE_SELECT_SHIFT # glossary: bit-field
          physical_page = @physical_pages[logical_nametable]
          (physical_page * NAMETABLE_SIZE) + (address & NAMETABLE_OFFSET_MASK) # glossary: low-bits
        end
      end
    end
  end
end
