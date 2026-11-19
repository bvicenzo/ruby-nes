# frozen_string_literal: true

module Ruby
  module Nes
    class Ppu
      # Secondary OAM (https://www.nesdev.org/wiki/PPU_sprite_evaluation): the "32-byte buffer for current sprites on
      # scanline", 8 slots of 4 bytes (Y, tile, attributes, X), "initialized to $FF" before each evaluation, which puts
      # the sprites it selects in "the next open slot". An empty slot reads $FF, so its pattern fetch is the "dummy
      # fetches to tile $FF" (https://www.nesdev.org/wiki/PPU_rendering); the hardware's first empty slot also keeps
      # sprite 63's Y, which only changes the fine row of that dummy fetch and is not modelled. Whether sprite 0 is
      # among the selected sprites is a flag of its own, "whether sprite 0 occurs on the _next_ scanline"
      # (https://www.nesdev.org/wiki/PPU_OAM). Hot path: filled once per scanline, read by the sprite fetches.
      class SecondaryOam
        SIZE = 32
        EMPTY_BYTE = 0xFF
        # A slot holds a sprite's 4 bytes, laid out as in OAM.
        SLOT_SHIFT = Oam::SPRITE_SIZE_SHIFT

        # The number of sprites held, 0 to 8.
        attr_reader :count

        def initialize
          @bytes = Array.new(SIZE, EMPTY_BYTE)
          @count = 0
          @sprite_zero_selected = false
        end

        # Whether the slot holds sprite 0: "sprite 0, when it is within y range for the next scanline, always gets
        # assigned the first sprite output unit".
        def sprite_zero?(slot) = slot.zero? && @sprite_zero_selected

        # Back to no sprite, every byte $FF.
        def clear
          @bytes.fill(EMPTY_BYTE)
          @count = 0
          @sprite_zero_selected = false
        end

        # Puts a sprite's four bytes in the next open slot.
        def add(y_position, tile, attributes, x_position)
          slot_start = @count << SLOT_SHIFT # glossary: place-bit-field
          @bytes[slot_start] = y_position
          @bytes[slot_start + Oam::TILE_OFFSET] = tile
          @bytes[slot_start + Oam::ATTRIBUTES_OFFSET] = attributes
          @bytes[slot_start + Oam::X_POSITION_OFFSET] = x_position
          @count += 1
        end

        # Sprite 0 is among the sprites held, in slot 0.
        def select_sprite_zero
          @sprite_zero_selected = true
        end

        def y_position(slot)
          @bytes[slot << SLOT_SHIFT] # glossary: place-bit-field
        end

        def tile(slot)
          @bytes[(slot << SLOT_SHIFT) + Oam::TILE_OFFSET] # glossary: place-bit-field
        end

        def attributes(slot)
          @bytes[(slot << SLOT_SHIFT) + Oam::ATTRIBUTES_OFFSET] # glossary: place-bit-field
        end

        def x_position(slot)
          @bytes[(slot << SLOT_SHIFT) + Oam::X_POSITION_OFFSET] # glossary: place-bit-field
        end
      end
    end
  end
end
