# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # The sprite fetches of dots 257-320 (https://www.nesdev.org/wiki/PPU_rendering): for each slot of secondary OAM,
      # "Pattern table tile low" and "Pattern table tile high (8 bytes above pattern table tile low address)", then the
      # sprite's row goes into the line buffer. An empty slot reads $FF bytes, so its fetches are the "dummy fetches to
      # tile $FF", and it loads nothing: "the sprites are loaded with a transparent set of values instead". The row is
      # the scanline minus Y, the sprites being fetched on the scanline before the one they show on (Y is "delayed by
      # one scanline", https://www.nesdev.org/wiki/PPU_OAM). The address of a row depends on the sprite size: the Ppu
      # tells which SpritePatternAddress applies (PPUCTRL bit 5). SecondaryOam says which slot holds sprite 0.
      # Hot path: two fetches and one load per slot per rendered scanline.
      class SpriteFetcher
        HIGH_PLANE_OFFSET = 8

        # SpritePatternAddress::EightByEight or ::EightBySixteen.
        attr_writer :pattern_address

        def initialize(bus:, secondary_oam:, line:, pattern_address: SpritePatternAddress::EightByEight.new)
          @bus = bus
          @secondary_oam = secondary_oam
          @line = line
          @pattern_address = pattern_address
          @address = 0
          @pattern_low = 0
          @pattern_high = 0
        end

        def fetch_pattern_low(slot, scanline)
          row = scanline - @secondary_oam.y_position(slot)
          @address = @pattern_address.address(@secondary_oam.tile(slot), row, @secondary_oam.attributes(slot))
          @pattern_low = @bus.read(@address)
        end

        def fetch_pattern_high
          @pattern_high = @bus.read(@address + HIGH_PLANE_OFFSET)
        end

        # Puts the slot's fetched row into the line buffer; an empty slot puts nothing.
        def load_sprite(slot)
          return if slot >= @secondary_oam.count

          attributes = @secondary_oam.attributes(slot)
          sprite_zero = @secondary_oam.sprite_zero?(slot)
          @line.place(@secondary_oam.x_position(slot), @pattern_low, @pattern_high, attributes, sprite_zero)
        end
      end
    end
  end
end
