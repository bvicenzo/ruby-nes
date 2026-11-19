# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The search for a ninth sprite, step 3 of the sprite evaluation
      # (https://www.nesdev.org/wiki/PPU_sprite_evaluation), run once 8 sprites were found: "Starting at m = 0,
      # evaluate OAM[n][m] as a Y-coordinate"; "If the value is in range, set the sprite overflow flag"; "If the value is
      # not in range, increment n **and** m (without carry). If n overflows to 0" the search ends. "The m increment is
      # a hardware bug": after the first sprite the scan reads OAM "diagonally", tile, attribute and X bytes as if they
      # were Y coordinates, which gives "both false positives and false negatives". Hot path: at most once per
      # scanline, a loop over the sprites left.
      class OverflowSearch
        def initialize(oam:)
          @oam = oam
        end

        # Whether the scan from sprite `first_sprite` finds a byte in range of the scanline before the end of OAM.
        # m wraps within a sprite's 4 bytes (Oam::SPRITE_BYTE_MASK) without carrying into n.
        def found?(first_sprite, scanline, height)
          sprite = first_sprite
          byte = 0
          while sprite < Oam::SPRITE_COUNT
            y_position = @oam.byte((sprite << Oam::SPRITE_SIZE_SHIFT) | byte) # glossary: place-bit-field, bitwise-or
            return true if SpriteRows.in_range?(y_position, scanline, height)

            sprite += 1
            byte = (byte + 1) & Oam::SPRITE_BYTE_MASK # glossary: low-bits
          end
          false
        end
      end
    end
  end
end
