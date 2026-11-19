# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Steps 1-2 of the sprite evaluation (https://www.nesdev.org/wiki/PPU_sprite_evaluation), run once per visible
      # scanline at dot 257 for the next one (plan 14, decision 2): secondary OAM "is initialized to $FF", then
      # "Starting at n = 0", each sprite whose Y is "in range" has its 4 bytes copied "into secondary OAM", until "exactly
      # 8 sprites have been found" and secondary OAM is "full". Sprite 0 in range is marked: the PPU tracks "whether
      # sprite 0 occurs on the _next_ scanline" (https://www.nesdev.org/wiki/PPU_OAM). With 8 found and sprites left, the
      # search for a ninth (step 3, OverflowSearch) starts at the next one and sets "the sprite overflow flag". The
      # sprite height, 8 or 16 (PPUCTRL bit 5, https://www.nesdev.org/wiki/PPU_registers), is told by the SpriteRenderer. Hot
      # path: a loop over OAM once per scanline.
      class SpriteEvaluation
        SPRITE_COUNT = Oam::SPRITE_COUNT
        SPRITES_PER_SCANLINE = 8

        # 8, or 16 for 8×16 sprites.
        attr_writer :sprite_height

        def initialize(oam:, secondary_oam:, status:, overflow_search: OverflowSearch.new(oam:),
                       sprite_height: SpritePatternAddress::EightByEight::HEIGHT)
          @oam = oam
          @secondary_oam = secondary_oam
          @status = status
          @overflow_search = overflow_search
          @sprite_height = sprite_height
        end

        # Selects the sprites of the scanline after `scanline`.
        def evaluate(scanline)
          @secondary_oam.clear
          next_sprite = select_sprites(scanline)
          return if next_sprite == SPRITE_COUNT

          @status.overflow_found if @overflow_search.found?(next_sprite, scanline, @sprite_height)
        end

        private

        # Copies the sprites in range into secondary OAM, up to 8; returns the sprite after the eighth, or 64 once every
        # sprite was read.
        def select_sprites(scanline)
          found = 0
          sprite = 0
          while sprite < SPRITE_COUNT
            address = sprite << Oam::SPRITE_SIZE_SHIFT # glossary: place-bit-field
            y_position = @oam.byte(address)
            sprite += 1
            next unless SpriteRows.in_range?(y_position, scanline, @sprite_height)

            copy_sprite(address, y_position)
            found += 1
            break if found == SPRITES_PER_SCANLINE
          end
          sprite
        end

        def copy_sprite(address, y_position)
          tile = @oam.byte(address + Oam::TILE_OFFSET)
          attributes = @oam.byte(address + Oam::ATTRIBUTES_OFFSET)
          @secondary_oam.add(y_position, tile, attributes, @oam.byte(address + Oam::X_POSITION_OFFSET))
          @secondary_oam.select_sprite_zero if address.zero?
        end
      end
    end
  end
end
